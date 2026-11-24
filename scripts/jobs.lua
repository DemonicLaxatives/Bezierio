--- Runs the heavy work (planning, drawing, building) a budgeted amount per tick.
---
--- GUI and input handlers never do this work themselves: they change data and call
--- state.changed / request_redraw / request_build. Each tick, for each player:
---   0. destroy retired render objects
---   1. curve or layers changed (revision) -> once edits have paused for a moment,
---      drop the plan and redraw from scratch; only the view changed -> redraw
---   2. draw what the planner has produced so far (capped share of the budget)
---   3. advance the planner: up to the curve samples if only the curve is shown,
---      the whole plan if the preview is on or a build is waiting for it
---   4. start a waiting build once its plan is done, and advance a running build
---   5. update the window's status and totals lines
---
--- All job state lives in storage.controllers[i].work as plain data, so it survives
--- save/load and runs identically on every multiplayer peer. The map editor starts
--- with ticks paused; nothing here runs until it is unpaused.
local state = require("scripts.state")
local draw = require("scripts.draw")
local planner = require("scripts.build.planner")
local executor = require("scripts.build.executor")
local blueprint = require("scripts.build.blueprint")
local curve_lib = require("scripts.curve.curve")
local window = require("scripts.gui.window")
local highlight = require("scripts.highlight")
local presets = require("scripts.presets")

local lib = {}

--- Work units per player per tick when the setting can't be read. Measured with
--- tests/bezierio-test/scenarios/bench: one unit is ~2-3 µs whatever the work, so
--- 1000 units is ~2.5-3 ms per tick (planning, drawing and building alike).
lib.DEFAULT_BUDGET = 1000

--- Share of the budget drawing may use, so the preview keeps up with the planner.
lib.DRAW_SHARE = 0.3

--- Ticks to wait after the last curve/layer edit before planning again, so that
--- dragging a slider doesn't restart the plan on every step.
lib.SETTLE_TICKS = 10

--- @return number
function lib.budget()
    local setting = settings.global["bezierio-work-budget"]
    return setting and setting.value --[[@as number]] or lib.DEFAULT_BUDGET
end

--- @param controller Controller
--- @return "plan"|"samples"|nil  # how far the planner needs to get
local function plan_needed(controller)
    local ui = controller.ui
    if ui.preview_build or controller.work.pending_build then return "plan" end
    if ui.draw_curve then return "samples" end
    return nil
end

--- What runs a build job: the executor (ghosts / instant), or the blueprint writer.
--- @param job BuildJob|BlueprintJob
local function runner(job)
    return job.kind == "blueprint" and blueprint or executor
end

--- @param player LuaPlayer
--- @param controller Controller
--- @param job BuildJob|BlueprintJob
local function report_build(player, controller, job)
    if job.aborted then return end
    if job.kind == "blueprint" then
        if job.error then
            player.print({ "bezierio-message." .. job.error })
        elseif job.result then
            player.print({ "bezierio-message.blueprint-done", tostring(job.result.entities), tostring(job.result.tiles) })
        end
        return
    end
    local result, plan = job.result, job.plan
    local message = job.output == "instant" and "bezierio-message.build-result-instant"
        or "bezierio-message.build-result"
    player.print({ message, tostring(result.placed), tostring(result.existing), tostring(result.blocked + plan.skipped) })
    if (result.covered or 0) > 0 then
        player.print({ "bezierio-message.covered", tostring(result.covered) })
    end
    if plan.gaps > 0 then
        player.print({ "bezierio-message.pole-gaps", tostring(plan.gaps) })
    end
    if plan.unpowered > 0 then
        player.print({ "bezierio-message.unpowered", tostring(plan.unpowered) })
    end
    if (plan.unfed or 0) > 0 then
        player.print({ "bezierio-message.unfed", tostring(plan.unfed) })
    end
    -- Mark them on the map (fading after the player's highlight setting).
    local kinds = {}
    if plan.unpowered > 0 then kinds[#kinds + 1] = "unpowered" end
    if (plan.unfed or 0) > 0 then kinds[#kinds + 1] = "unfed" end
    if #kinds > 0 then highlight.show(player, controller, plan, kinds, job.surface) end
end

--- What the blueprint carries to load the curve and preset back (as import
--- strings), unless the player turned that off.
--- @param player LuaPlayer
--- @param controller Controller
--- @param preset Preset
--- @return BlueprintSource|nil
local function blueprint_source(player, controller, preset)
    if not state.setting(player.index, "blueprint_source") then return nil end
    return {
        curve = helpers.encode_string(helpers.table_to_json(curve_lib.to_data(controller.curve))) --[[@as string]],
        preset = presets.export(preset),
    }
end

--- What's happening right now.
--- @param controller Controller
--- @return LocalisedString, string, number|nil  # caption, a key to detect changes, and progress (0..1) while planning or building
local function status_of(controller)
    local work = controller.work
    local pending = work.pending_build
    -- the queued command, after what's happening
    local function with_queue(caption, word)
        if not pending then return caption end
        return { "", caption, " · ", { word, { "label.command-" .. pending } } }
    end
    if work.build then
        local pct = math.floor(runner(work.build).progress(work.build) * 100)
        local running = work.build.kind == "blueprint" and "blueprint" or work.build.mode
        local caption = { "", { "label.status-building", tostring(pct) }, " (", { "label.command-" .. running }, ")" }
        return with_queue(caption, "label.status-next"), "b" .. pct .. running .. (pending or ""), pct / 100
    end
    local plan_job = work.plan
    if (pending or controller.ui.preview_build) and plan_job and not plan_job.plan.done then
        local pct = math.floor(planner.progress(plan_job) * 100)
        return with_queue({ "label.status-planning", tostring(pct) }, "label.status-then"), "p" .. pct .. (pending or ""), pct / 100
    end
    if work.revision ~= controller.revision and plan_needed(controller) then
        return with_queue({ "label.status-planning", "0" }, "label.status-then"), "p0" .. (pending or ""), 0
    end
    if controller.ui.preview_build and work.draw.preview_count >= draw.MAX_PREVIEW_OBJECTS then
        return { "label.status-preview-partial" }, "cap"
    end
    return "", ""
end

--- The item for a layer, as rich text.
--- @param layer Layer
--- @return string
local function item_text(layer)
    local quality = layer.quality or "normal"
    if quality == "normal" then return string.format("[item=%s]", layer.placed_by) end
    return string.format("[item=%s,quality=%s]", layer.placed_by, quality)
end

--- What the build needs: items summed over layers (by item and quality), and the
--- same per layer for the tooltip.
--- @param controller Controller
--- @param plan BuildPlan
--- @return string, LocalisedString  # caption, tooltip
local function items_of(controller, plan)
    local layers = state.layers_of(controller)
    local keys = {}
    for idx in pairs(plan.counts) do table.insert(keys, idx) end
    table.sort(keys, function(a, b) return a > b end)

    local totals, order, rows = {}, {}, { "", { "label.totals-per-layer" } }
    for _, idx in ipairs(keys) do
        local layer = layers[idx]
        if layer and layer.placed_by then
            local item, count = item_text(layer), plan.counts[idx]
            if not totals[item] then table.insert(order, item) end
            totals[item] = (totals[item] or 0) + count
            -- Undergrounds, pumps.
            for extra, n in pairs(plan.extra_counts and plan.extra_counts[idx] or {}) do
                local text = string.format("[item=%s]", extra)
                if not totals[text] then table.insert(order, text) end
                totals[text] = (totals[text] or 0) + n
            end
            -- Ammo the turrets request.
            if layer.ammo and layer.ammo_inventory then
                local ammo = string.format("[item=%s]", layer.ammo)
                if not totals[ammo] then table.insert(order, ammo) end
                totals[ammo] = (totals[ammo] or 0) + count * (layer.ammo_count or 0)
            end
            -- A LocalisedString takes at most 20 parameters.
            if #rows <= 20 then
                table.insert(rows, { "label.totals-layer", tostring(idx), item, tostring(count) })
            end
        end
    end
    local parts = {}
    for _, item in ipairs(order) do table.insert(parts, string.format("%s×%d", item, totals[item])) end
    return table.concat(parts, " "), rows
end

--- The summary pane while planning or building: the progress and a bar, in place
--- of the summary.
--- @param player LuaPlayer
--- @param caption LocalisedString
--- @param fraction number
local function show_progress(player, caption, fraction)
    local pane = window.find(player, "totals")
    if not pane then return end
    pane.visible = true
    for _, child in pairs(pane.children) do
        child.visible = child.name == "totals_head" or child.name == "totals_progress"
    end
    local length = window.find(player, "totals_length")
    if length then length.caption, length.tooltip = caption, "" end
    local bar = window.find(player, "totals_progress")
    if bar then bar.value = fraction end
    -- Cancel: only with a build running or queued.
    local work = state.get(player.index).work
    local cancel = window.find(player, "build_cancel")
    if cancel then cancel.visible = work.build ~= nil or work.pending_build ~= nil end
end

--- @param player LuaPlayer
--- @param controller Controller
--- @param plan BuildPlan|nil  # nil clears the totals
local function show_totals(player, controller, plan)
    local length = window.find(player, "totals_length")
    local items = window.find(player, "totals_items")
    local bends = window.find(player, "totals_bends")
    local gaps = window.find(player, "totals_gaps")
    local unpowered = window.find(player, "totals_unpowered")
    local unfed = window.find(player, "totals_unfed")
    if not (length and items and bends and gaps and unpowered and unfed) then return end
    local pane = window.find(player, "totals")
    if pane then pane.visible = plan ~= nil end
    -- (back from showing progress: the summary's rows, the item list only wide)
    local narrow = controller.ui.narrow == true
    for _, name in ipairs({ "totals_line_items", "totals_items" }) do
        local element = window.find(player, name)
        if element then element.visible = not narrow end
    end
    local bar, warning_row = window.find(player, "totals_progress"), window.find(player, "totals_warnings")
    if bar then bar.visible = false end
    local cancel = window.find(player, "build_cancel")
    if cancel then cancel.visible = false end
    if warning_row then warning_row.visible = true end
    if not plan then
        length.caption, items.caption, items.tooltip, length.tooltip = "", "", "", ""
        bends.visible, gaps.visible, unpowered.visible, unfed.visible = false, false, false, false
        return
    end
    length.caption = { "label.totals", string.format("%.0f", plan.length) }
    items.caption, items.tooltip = items_of(controller, plan)
    -- (the narrow window hides the item list: it's in the length's tooltip)
    length.tooltip = { "", items.caption, "\n", items.tooltip }
    bends.caption = { "label.totals-bends", tostring(#plan.warnings) }
    bends.visible = #plan.warnings > 0
    gaps.caption = { "label.totals-gaps", tostring(plan.gaps) }
    gaps.visible = plan.gaps > 0
    unpowered.caption = { "label.totals-unpowered", tostring(plan.unpowered) }
    unpowered.visible = plan.unpowered > 0
    unfed.caption = { "label.totals-unfed", tostring(plan.unfed or 0) }
    unfed.visible = (plan.unfed or 0) > 0
    -- (a line above the warnings, when there are any)
    local line = window.find(player, "totals_line_warnings")
    if line then line.visible = bends.visible or gaps.visible or unpowered.visible or unfed.visible end
end

--- @param player LuaPlayer
--- @param controller Controller
local function update_window(player, controller)
    if not window.get(player) then return end
    local work = controller.work
    local caption, key, fraction = status_of(controller)
    if key ~= work.status then
        work.status = key
        local label = window.find(player, "status")
        if label then
            -- (progress goes into the summary pane instead)
            label.caption = fraction and "" or caption
            label.visible = fraction == nil and key ~= ""
        end
        if fraction then show_progress(player, caption, fraction) end
    end
    if fraction then
        -- (-1: no revision's totals are shown, so the summary comes back when done)
        work.totals_revision = -1
        return
    end
    -- Totals and warnings for any finished plan: the preview's, or the one a build
    -- just used (with the preview off).
    local plan_job = work.plan
    if plan_job and plan_job.plan.done then
        if work.totals_revision ~= work.revision then
            work.totals_revision = work.revision
            show_totals(player, controller, plan_job.plan)
        end
    elseif work.totals_revision then
        work.totals_revision = nil
        show_totals(player, controller, nil)
    end
end

--- Advance one player's jobs.
--- @param player LuaPlayer
--- @param controller Controller
function lib.update(player, controller)
    local work = controller.work
    local budget = lib.budget()
    if controller.ui.reopen_main then window.focus_main(player, controller.ui) end

    budget = budget - draw.step_trash(player.index, budget * draw.TRASH_SHARE)

    if work.revision ~= controller.revision
        and game.tick - (controller.changed_tick or 0) >= lib.SETTLE_TICKS then
        work.revision = controller.revision
        work.plan = nil
        controller.redraw = true
        -- The totals and warnings go with the plan, and so do the marks.
        highlight.hide_all(player, controller)
    end
    if controller.redraw then
        controller.redraw, controller.redraw_points = false, nil
        draw.reset(player, controller)
    elseif controller.redraw_points then
        controller.redraw_points = nil
        draw.redraw_points(player, controller)
    end

    local settled = work.revision == controller.revision
    local needed = plan_needed(controller)
    if settled and needed and not work.plan and curve_lib.is_drawable(controller.curve) then
        local layers = state.layers_of(controller)
        state.refresh_layers(layers)
        work.plan = planner.new_job(controller.curve, layers)
    end

    local plan_job = work.plan
    if plan_job and settled and budget > 0 then
        local used = draw.step(player, controller, plan_job, budget * lib.DRAW_SHARE)
        budget = budget - used
        if needed and budget > 0 then
            local _, plan_used = planner.step(plan_job, budget, needed == "samples" and "tangents" or nil)
            budget = budget - plan_used
        end
    end

    -- (a command waits for a build already running)
    if work.pending_build and settled and not work.build then
        if not curve_lib.is_drawable(controller.curve) then
            player.print({ "bezierio-message.need-two-points" })
            work.pending_build = nil
        elseif plan_job and plan_job.plan.done then
            for _, idx in ipairs(plan_job.plan.unsupported) do
                player.print({ "bezierio-message.unsupported-layer", tostring(idx) })
            end
            if work.pending_build == "blueprint" then
                local preset = controller.presets[controller.ui.preset_index]
                work.build = blueprint.new_job(player, plan_job.plan, "Bézierio: " .. preset.name,
                    blueprint_source(player, controller, preset))
            else
                work.build = executor.new_job(player, plan_job.plan, work.pending_build --[[@as BezierioBuildMode]],
                    state.setting(player.index, "cover_tiles"))
            end
            work.pending_build = nil
        end
    end

    local build = work.build
    if build and budget > 0 then
        local done, used = runner(build).step(build, budget)
        budget = budget - (used or 0)
        if done then
            report_build(player, controller, build)
            work.build = nil
        end
    end

    if work.highlight and budget > 0 then
        budget = budget - highlight.step(player, controller, budget)
    end

    update_window(player, controller)
end

--- Nothing left to do for this player (used by tests to wait for results).
--- @param player_index integer
--- @param controller Controller
--- @return boolean
function lib.is_idle(player_index, controller)
    local work = controller.work
    if controller.redraw or controller.redraw_points or work.revision ~= controller.revision then return false end
    if work.pending_build or work.build or highlight.pending(controller) then return false end
    local sprites = storage.sprites and storage.sprites[player_index]
    if sprites and sprites.trash and #sprites.trash > 0 then return false end
    local needed = plan_needed(controller)
    if not needed then return true end
    if not work.plan then return not curve_lib.is_drawable(controller.curve) end
    local plan_job = work.plan --[[@as PlannerJob]]
    if needed == "plan" and not plan_job.plan.done then return false end
    if needed == "samples" and plan_job.stage == "sample" then return false end

    local progress = work.draw
    if controller.ui.draw_curve and not progress.curve_finished then return false end
    if controller.ui.preview_build and not draw.preview_complete(progress, plan_job.plan) then return false end
    return true
end

script.on_event(defines.events.on_tick, function()
    state.ensure_rebuilt()
    for player_index, controller in pairs(storage.controllers) do
        local player = game.get_player(player_index)
        if player and player.valid then
            lib.update(player, controller)
        end
    end
end)

return lib
