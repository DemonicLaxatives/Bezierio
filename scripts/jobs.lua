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
--- @param job BuildJob|BlueprintJob
local function report_build(player, job)
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
    if plan.gaps > 0 then
        player.print({ "bezierio-message.pole-gaps", tostring(plan.gaps) })
    end
    if plan.unpowered > 0 then
        player.print({ "bezierio-message.unpowered", tostring(plan.unpowered) })
    end
end

--- The status line: what's happening right now.
--- @param controller Controller
--- @return LocalisedString, string  # caption, and a key to detect changes
local function status_of(controller)
    local work = controller.work
    if work.build then
        local pct = math.floor(runner(work.build).progress(work.build) * 100)
        return { "label.status-building", tostring(pct) }, "b" .. pct
    end
    local plan_job = work.plan
    if (work.pending_build or controller.ui.preview_build) and plan_job and not plan_job.plan.done then
        local pct = math.floor(planner.progress(plan_job) * 100)
        return { "label.status-planning", tostring(pct) }, "p" .. pct
    end
    if work.revision ~= controller.revision and plan_needed(controller) then
        return { "label.status-planning", "0" }, "p0"
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

--- @param player LuaPlayer
--- @param controller Controller
--- @param plan BuildPlan|nil  # nil clears the totals
local function show_totals(player, controller, plan)
    local length = window.find(player, "totals_length")
    local items = window.find(player, "totals_items")
    local bends = window.find(player, "totals_bends")
    local gaps = window.find(player, "totals_gaps")
    local unpowered = window.find(player, "totals_unpowered")
    if not (length and items and bends and gaps and unpowered) then return end
    if not plan then
        length.caption, items.caption, items.tooltip = "", "", ""
        bends.visible, gaps.visible, unpowered.visible = false, false, false
        return
    end
    length.caption = { "label.totals", string.format("%.0f", plan.length) }
    items.caption, items.tooltip = items_of(controller, plan)
    bends.caption = { "label.totals-bends", tostring(#plan.warnings) }
    bends.visible = #plan.warnings > 0
    gaps.caption = { "label.totals-gaps", tostring(plan.gaps) }
    gaps.visible = plan.gaps > 0
    unpowered.caption = { "label.totals-unpowered", tostring(plan.unpowered) }
    unpowered.visible = plan.unpowered > 0
end

--- @param player LuaPlayer
--- @param controller Controller
local function update_window(player, controller)
    if not window.get(player) then return end
    local work = controller.work
    local caption, key = status_of(controller)
    if key ~= work.status then
        work.status = key
        local label = window.find(player, "status")
        if label then label.caption = caption end
    end
    local plan_job = work.plan
    if plan_job and plan_job.plan.done and controller.ui.preview_build then
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

    budget = budget - draw.step_trash(player.index, budget)

    if work.revision ~= controller.revision
        and game.tick - (controller.changed_tick or 0) >= lib.SETTLE_TICKS then
        work.revision = controller.revision
        work.plan = nil
        controller.redraw = true
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
        work.plan = planner.new_job(controller.curve, state.layers_of(controller))
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

    if work.pending_build and settled then
        if not curve_lib.is_drawable(controller.curve) then
            player.print({ "bezierio-message.need-two-points" })
            work.pending_build = nil
        elseif plan_job and plan_job.plan.done then
            for _, idx in ipairs(plan_job.plan.unsupported) do
                player.print({ "bezierio-message.unsupported-layer", tostring(idx) })
            end
            if work.pending_build == "blueprint" then
                local preset = controller.presets[controller.ui.preset_index]
                work.build = blueprint.new_job(player, plan_job.plan, "Bézierio: " .. preset.name)
            else
                work.build = executor.new_job(player, plan_job.plan, work.pending_build)
            end
            work.pending_build = nil
        end
    end

    local build = work.build
    if build and budget > 0 then
        local done = runner(build).step(build, budget)
        if done then
            report_build(player, build)
            work.build = nil
        end
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
    if work.pending_build or work.build then return false end
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
