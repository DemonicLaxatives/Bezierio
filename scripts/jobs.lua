--- Runs the heavy work (planning, drawing, building) a budgeted amount per tick.
---
--- GUI and input handlers never do this work themselves: they change data and call
--- state.changed / request_redraw / request_build. Each tick, for each player:
---   1. curve or layers changed (revision) -> drop the plan, redraw from scratch;
---      only the view changed (redraw)    -> redraw from scratch
---   2. draw what the planner has produced so far (capped share of the budget)
---   3. advance the planner: up to the curve samples if only the curve is shown,
---      the whole plan if the preview is on or a build is waiting for it
---   4. start a waiting build once its plan is done, and advance a running build
---
--- All job state lives in storage.controllers[i].work as plain data, so it survives
--- save/load and runs identically on every multiplayer peer.
local state = require("scripts.state")
local draw = require("scripts.draw")
local planner = require("scripts.build.planner")
local executor = require("scripts.build.executor")
local curve_lib = require("scripts.curve.curve")

local lib = {}

--- Work units per player per tick (roughly: 1 unit ~ a few microseconds).
lib.BUDGET = 3000

--- Share of the budget drawing may use, so the preview keeps up with the planner.
lib.DRAW_SHARE = 0.3

--- @param controller Controller
--- @return "plan"|"samples"|nil  # how far the planner needs to get
local function plan_needed(controller)
    local ui = controller.ui
    if ui.preview_build or controller.work.pending_build then return "plan" end
    if ui.draw_curve then return "samples" end
    return nil
end

--- @param player LuaPlayer
--- @param result BuildResult
--- @param job BuildJob
--- @param plan BuildPlan
local function report_build(player, job, result, plan)
    local message = job.output == "instant" and "bezierio-message.build-result-instant"
        or "bezierio-message.build-result"
    player.print({ message, tostring(result.placed), tostring(result.existing), tostring(result.blocked + plan.skipped) })
end

--- Advance one player's jobs.
--- @param player LuaPlayer
--- @param controller Controller
function lib.update(player, controller)
    local work = controller.work
    local budget = lib.BUDGET

    if work.revision ~= controller.revision then
        work.revision = controller.revision
        work.plan = nil
        controller.redraw = true
    end
    if controller.redraw then
        controller.redraw = false
        draw.reset(player, controller)
    end

    local needed = plan_needed(controller)
    if needed and not work.plan and curve_lib.is_drawable(controller.curve) then
        work.plan = planner.new_job(controller.curve, state.layers_of(controller))
    end

    local plan_job = work.plan
    if plan_job then
        local used = draw.step(player, controller, plan_job, budget * lib.DRAW_SHARE)
        budget = budget - used
        if needed and budget > 0 then
            local _, plan_used = planner.step(plan_job, budget, needed == "samples" and "tangents" or nil)
            budget = budget - plan_used
        end
    end

    if work.pending_build then
        if not curve_lib.is_drawable(controller.curve) then
            player.print({ "bezierio-message.need-two-points" })
            work.pending_build = nil
        elseif plan_job and plan_job.plan.done then
            for _, idx in ipairs(plan_job.plan.unsupported) do
                player.print({ "bezierio-message.unsupported-layer", tostring(idx) })
            end
            work.build = executor.new_job(player, plan_job.plan, work.pending_build)
            work.pending_build = nil
        end
    end

    local build = work.build
    if build and budget > 0 then
        local done = executor.step(build, budget)
        if done then
            report_build(player, build, build.result, build.plan)
            work.build = nil
        end
    end
end

--- Nothing left to do for this player (used by tests to wait for results).
--- @param controller Controller
--- @return boolean
function lib.is_idle(controller)
    local work = controller.work
    if controller.redraw or work.revision ~= controller.revision then return false end
    if work.pending_build or work.build then return false end
    local needed = plan_needed(controller)
    if not needed then return true end
    if not work.plan then return not curve_lib.is_drawable(controller.curve) end
    local plan_job = work.plan --[[@as PlannerJob]]
    if needed == "plan" and not plan_job.plan.done then return false end
    if needed == "samples" and plan_job.stage == "sample" then return false end

    -- Drawing caught up?
    local progress = work.draw
    if controller.ui.draw_curve and not progress.curve_finished then return false end
    if controller.ui.preview_build then
        local plan = plan_job.plan
        local all_drawn = progress.preview_count >= draw.MAX_PREVIEW_OBJECTS
            or (progress.preview_tiles >= #plan.tiles and progress.preview_entities >= #plan.entities)
        if not all_drawn then return false end
    end
    return true
end

script.on_event(defines.events.on_tick, function()
    state.ensure()
    for player_index, controller in pairs(storage.controllers) do
        local player = game.get_player(player_index)
        if player and player.valid then
            lib.update(player, controller)
        end
    end
end)

return lib
