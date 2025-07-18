/obj/effect/abstract/liquid_turf
	name = "liquid"
	icon = 'modular_skyrat/modules/liquids/icons/obj/effects/liquid.dmi'
	icon_state = "water-0"
	base_icon_state = "water"
	anchored = TRUE
	plane = FLOOR_PLANE
	layer = ABOVE_OPEN_TURF_LAYER
	appearance_flags = TILE_BOUND
	color = "#DDF"

	//For being on fire
	light_range = 0
	light_power = 1
	light_color = LIGHT_COLOR_FIRE

	smoothing_flags = SMOOTH_BITMASK
	smoothing_groups = SMOOTH_GROUP_WATER
	canSmoothWith = SMOOTH_GROUP_WATER + SMOOTH_GROUP_WINDOW_FULLTILE + SMOOTH_GROUP_WALLS

	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	var/height = 1
	var/only_big_diffs = 1
	var/turf/my_turf
	var/liquid_state = LIQUID_STATE_PUDDLE
	var/has_cached_share = FALSE

	var/attrition = 0

	var/immutable = FALSE

	var/list/reagent_list = list()
	var/total_reagents = 0
	var/temp = T20C

	var/fire_state = LIQUID_FIRE_STATE_NONE

	var/no_effects = FALSE

	/// State-specific message chunks for examine_turf()
	var/static/list/liquid_state_messages = list(
		"[LIQUID_STATE_PUDDLE]" = "a puddle of $",
		"[LIQUID_STATE_ANKLES]" = "$ going [span_warning("up to your ankles")]",
		"[LIQUID_STATE_WAIST]" = "$ going [span_warning("up to your waist")]",
		"[LIQUID_STATE_SHOULDERS]" = "$ going [span_warning("up to your shoulders")]",
		"[LIQUID_STATE_FULLTILE]" = "$ going [span_danger("over your head")]",
	)

/obj/effect/abstract/liquid_turf/onShuttleMove(turf/newT, turf/oldT, list/movement_force, move_dir, obj/docking_port/stationary/old_dock, obj/docking_port/mobile/moving_dock)
	return

/obj/effect/abstract/liquid_turf/proc/check_fire(hotspotted = FALSE)
	var/my_burn_power = get_burn_power(hotspotted)
	if(!my_burn_power)
		if(fire_state)
			//Set state to 0
			set_fire_state(LIQUID_FIRE_STATE_NONE)
		return FALSE
	//Calculate appropriate state
	var/new_state = LIQUID_FIRE_STATE_SMALL
	switch(my_burn_power)
		if(0 to 7)
			new_state = LIQUID_FIRE_STATE_SMALL
		if(7 to 8)
			new_state = LIQUID_FIRE_STATE_MILD
		if(8 to 9)
			new_state = LIQUID_FIRE_STATE_MEDIUM
		if(9 to 10)
			new_state = LIQUID_FIRE_STATE_HUGE
		if(10 to INFINITY)
			new_state = LIQUID_FIRE_STATE_INFERNO

	if(fire_state != new_state)
		set_fire_state(new_state)

	return TRUE

/obj/effect/abstract/liquid_turf/proc/set_fire_state(new_state)
	fire_state = new_state
	switch(fire_state)
		if(LIQUID_FIRE_STATE_NONE)
			set_light_range(0)
		if(LIQUID_FIRE_STATE_SMALL)
			set_light_range(LIGHT_RANGE_FIRE)
		if(LIQUID_FIRE_STATE_MILD)
			set_light_range(LIGHT_RANGE_FIRE)
		if(LIQUID_FIRE_STATE_MEDIUM)
			set_light_range(LIGHT_RANGE_FIRE)
		if(LIQUID_FIRE_STATE_HUGE)
			set_light_range(LIGHT_RANGE_FIRE)
		if(LIQUID_FIRE_STATE_INFERNO)
			set_light_range(LIGHT_RANGE_FIRE)
	update_light()
	update_icon(UPDATE_OVERLAYS)

/obj/effect/abstract/liquid_turf/proc/get_burn_power(hotspotted = FALSE)
	//We are not on fire and werent ignited by a hotspot exposure, no fire pls
	if(!hotspotted && !fire_state)
		return FALSE
	var/total_burn_power = 0
	var/datum/reagent/R //Faster declaration
	for(var/reagent_type in reagent_list)
		R = reagent_type
		var/burn_power = initial(R.liquid_fire_power)
		if(burn_power)
			total_burn_power += burn_power * reagent_list[reagent_type]
	if(!total_burn_power)
		return FALSE
	total_burn_power /= total_reagents //We get burn power per unit.
	if(total_burn_power <= REQUIRED_FIRE_POWER_PER_UNIT)
		return FALSE
	//Finally, we burn
	return total_burn_power

/obj/effect/abstract/liquid_turf/extinguish()
	. = ..()
	if(fire_state)
		set_fire_state(LIQUID_FIRE_STATE_NONE)

/obj/effect/abstract/liquid_turf/proc/process_fire()
	if(!fire_state)
		SSliquids.processing_fire -= my_turf
	var/old_state = fire_state
	if(!check_fire())
		SSliquids.processing_fire -= my_turf
	//Try spreading
	if(fire_state == old_state) //If an extinguisher made our fire smaller, dont spread, else it's too hard to put out
		for(var/turf/adjacent_turf in my_turf.atmos_adjacent_turfs)
			if(adjacent_turf.liquids && !adjacent_turf.liquids.fire_state && adjacent_turf.liquids.check_fire(TRUE))
				SSliquids.processing_fire[adjacent_turf] = TRUE
	//Burn our resources
	var/datum/reagent/reagent //Faster declaration
	var/burn_rate
	for(var/reagent_type in reagent_list)
		reagent = reagent_type
		burn_rate = initial(reagent.liquid_fire_burnrate)
		if(burn_rate)
			var/amt = reagent_list[reagent_type]
			if(burn_rate >= amt)
				reagent_list -= reagent_type
				total_reagents -= amt
			else
				reagent_list[reagent_type] -= burn_rate
				total_reagents -= burn_rate

	my_turf.hotspot_expose((T20C+50) + (50*fire_state), 125)
	for(var/atom/content in my_turf.contents)
		if(!QDELETED(content))
			content.fire_act((T20C+50) + (50*fire_state), 125)

	if(reagent_list.len == 0)
		qdel(src, TRUE)
	else
		has_cached_share = FALSE
		if(!my_turf.lgroup)
			calculate_height()
			set_reagent_color_for_liquid()

/obj/effect/abstract/liquid_turf/proc/process_evaporation()
	if(immutable)
		SSliquids.evaporation_queue -= my_turf
		return
	//We're in a group. dont try and evaporate
	if(my_turf.lgroup)
		SSliquids.evaporation_queue -= my_turf
		return
	if(liquid_state != LIQUID_STATE_PUDDLE)
		SSliquids.evaporation_queue -= my_turf
		return
	//See if any of our reagents evaporates
	var/any_change = FALSE
	var/datum/reagent/R //Faster declaration
	for(var/reagent_type in reagent_list)
		R = reagent_type
		//We evaporate. bye bye
		if(initial(R.evaporates))
			total_reagents -= reagent_list[reagent_type]
			reagent_list -= reagent_type
			any_change = TRUE
	if(!any_change)
		SSliquids.evaporation_queue -= my_turf
		return
	//No total reagents. Commit death
	if(reagent_list.len == 0)
		qdel(src, TRUE)
	//Reagents still left. Recalculte height and color and remove us from the queue
	else
		has_cached_share = FALSE
		SSliquids.evaporation_queue -= my_turf
		calculate_height()
		set_reagent_color_for_liquid()

/obj/effect/abstract/liquid_turf/forceMove(atom/destination, no_tp=FALSE, harderforce = FALSE)
	if(harderforce)
		. = ..()

/**
 * Makes and returns the liquid effect overlay.
 *
 * Arguments:
 * * overlay_state - the icon state of the new overlay
 * * overlay_layer - the layer
 * * overlay_plane - the plane
 */
/obj/effect/abstract/liquid_turf/proc/make_liquid_overlay(overlay_state, overlay_layer, overlay_plane)
	PRIVATE_PROC(TRUE)

	return mutable_appearance(
		'modular_skyrat/modules/liquids/icons/obj/effects/liquid_overlays.dmi',
		overlay_state,
		overlay_layer,
		src,
		overlay_plane,
	)

/**
 * Returns a list of over and underlays for different liquid states.
 *
 * Arguments:
 * * state - the stage number.
 * * has_top - if this stage has a top.
 */
/obj/effect/abstract/liquid_turf/proc/make_state_layer(state, has_top)
	PRIVATE_PROC(TRUE)

	. = list(make_liquid_overlay("stage[state]_bottom", ABOVE_MOB_LAYER, GAME_PLANE))

	if(!has_top)
		return

	. += make_liquid_overlay("stage[state]_top", TABLE_LAYER + 0.05, GAME_PLANE)

/obj/effect/abstract/liquid_turf/proc/set_new_liquid_state(new_state)
	liquid_state = new_state
	if(!isnull(my_turf))
		my_turf.liquids_change(new_state)
	update_icon(UPDATE_OVERLAYS)

/obj/effect/abstract/liquid_turf/update_overlays()
	. = ..()

	if(no_effects)
		return

	switch(liquid_state)
		if(LIQUID_STATE_ANKLES)
			. += make_state_layer(1, has_top = TRUE)
		if(LIQUID_STATE_WAIST)
			. += make_state_layer(2, has_top = TRUE)
		if(LIQUID_STATE_SHOULDERS)
			. += make_state_layer(3, has_top = TRUE)
		if(LIQUID_STATE_FULLTILE)
			. += make_state_layer(4, has_top = FALSE)

	var/mutable_appearance/shine = mutable_appearance(icon, "shine", offset_spokesman = src, alpha = 32, appearance_flags = RESET_COLOR|RESET_ALPHA)
	shine.blend_mode = BLEND_ADD
	. += shine

	//Add a fire overlay too

	if(fire_state == LIQUID_FIRE_STATE_NONE)
		return

	var/fire_icon_state
	switch(fire_state)
		if(LIQUID_FIRE_STATE_SMALL)
			fire_icon_state = "fire_small"
		if(LIQUID_FIRE_STATE_MILD)
			fire_icon_state = "fire_small"
		if(LIQUID_FIRE_STATE_MEDIUM)
			fire_icon_state = "fire_medium"
		if(LIQUID_FIRE_STATE_HUGE)
			fire_icon_state = "fire_big"
		if(LIQUID_FIRE_STATE_INFERNO)
			fire_icon_state = "fire_big"

	. += mutable_appearance(icon, fire_icon_state, BELOW_MOB_LAYER, src, GAME_PLANE, appearance_flags = RESET_COLOR|RESET_ALPHA)
	. += emissive_appearance(icon, fire_icon_state, src, alpha = src.alpha)

//Takes a flat of our reagents and returns it, possibly qdeling our liquids
/obj/effect/abstract/liquid_turf/proc/take_reagents_flat(flat_amount)
	var/datum/reagents/tempr = new(10000)
	if(flat_amount >= total_reagents)
		tempr.add_noreact_reagent_list(reagent_list)
		qdel(src, TRUE)
	else
		var/fraction = flat_amount/total_reagents
		var/passed_list = list()
		for(var/reagent_type in reagent_list)
			var/amount = fraction * reagent_list[reagent_type]
			reagent_list[reagent_type] -= amount
			total_reagents -= amount
			passed_list[reagent_type] = amount
		tempr.add_noreact_reagent_list(passed_list)
		has_cached_share = FALSE
	tempr.chem_temp = temp
	return tempr

/obj/effect/abstract/liquid_turf/immutable/take_reagents_flat(flat_amount)
	return simulate_reagents_flat(flat_amount)

//Returns a reagents holder with all the reagents with a higher volume than the threshold
/obj/effect/abstract/liquid_turf/proc/simulate_reagents_threshold(amount_threshold)
	var/datum/reagents/tempr = new(10000)
	var/passed_list = list()
	for(var/reagent_type in reagent_list)
		var/amount = reagent_list[reagent_type]
		if(amount_threshold && amount < amount_threshold)
			continue
		passed_list[reagent_type] = amount
	tempr.add_noreact_reagent_list(passed_list)
	tempr.chem_temp = temp
	return tempr

//Returns a flat of our reagents without any effects on the liquids
/obj/effect/abstract/liquid_turf/proc/simulate_reagents_flat(flat_amount)
	var/datum/reagents/tempr = new(10000)
	if(flat_amount >= total_reagents)
		tempr.add_noreact_reagent_list(reagent_list)
	else
		var/fraction = flat_amount/total_reagents
		var/passed_list = list()
		for(var/reagent_type in reagent_list)
			var/amount = fraction * reagent_list[reagent_type]
			passed_list[reagent_type] = amount
		tempr.add_noreact_reagent_list(passed_list)
	tempr.chem_temp = temp
	return tempr

/obj/effect/abstract/liquid_turf/fire_act(temperature, volume)
	if(!fire_state)
		if(check_fire(TRUE))
			SSliquids.processing_fire[my_turf] = TRUE

/obj/effect/abstract/liquid_turf/proc/set_reagent_color_for_liquid()
	color = mix_color_from_reagent_list(reagent_list)

/obj/effect/abstract/liquid_turf/proc/calculate_height()
	var/new_height = CEILING(total_reagents, 1)/LIQUID_HEIGHT_DIVISOR
	set_height(new_height)
	var/determined_new_state
	//We add the turf height if it's positive to state calculations
	if(my_turf.turf_height > 0)
		new_height += my_turf.turf_height
	switch(new_height)
		if(0 to LIQUID_ANKLES_LEVEL_HEIGHT-1)
			determined_new_state = LIQUID_STATE_PUDDLE
		if(LIQUID_ANKLES_LEVEL_HEIGHT to LIQUID_WAIST_LEVEL_HEIGHT-1)
			determined_new_state = LIQUID_STATE_ANKLES
		if(LIQUID_WAIST_LEVEL_HEIGHT to LIQUID_SHOULDERS_LEVEL_HEIGHT-1)
			determined_new_state = LIQUID_STATE_WAIST
		if(LIQUID_SHOULDERS_LEVEL_HEIGHT to LIQUID_FULLTILE_LEVEL_HEIGHT-1)
			determined_new_state = LIQUID_STATE_SHOULDERS
		if(LIQUID_FULLTILE_LEVEL_HEIGHT to INFINITY)
			determined_new_state = LIQUID_STATE_FULLTILE
	if(determined_new_state != liquid_state)
		set_new_liquid_state(determined_new_state)

/obj/effect/abstract/liquid_turf/immutable/calculate_height()
	var/new_height = CEILING(total_reagents, 1)/LIQUID_HEIGHT_DIVISOR
	set_height(new_height)
	var/determined_new_state
	switch(new_height)
		if(0 to LIQUID_ANKLES_LEVEL_HEIGHT-1)
			determined_new_state = LIQUID_STATE_PUDDLE
		if(LIQUID_ANKLES_LEVEL_HEIGHT to LIQUID_WAIST_LEVEL_HEIGHT-1)
			determined_new_state = LIQUID_STATE_ANKLES
		if(LIQUID_WAIST_LEVEL_HEIGHT to LIQUID_SHOULDERS_LEVEL_HEIGHT-1)
			determined_new_state = LIQUID_STATE_WAIST
		if(LIQUID_SHOULDERS_LEVEL_HEIGHT to LIQUID_FULLTILE_LEVEL_HEIGHT-1)
			determined_new_state = LIQUID_STATE_SHOULDERS
		if(LIQUID_FULLTILE_LEVEL_HEIGHT to INFINITY)
			determined_new_state = LIQUID_STATE_FULLTILE
	if(determined_new_state != liquid_state)
		set_new_liquid_state(determined_new_state)

/obj/effect/abstract/liquid_turf/proc/set_height(new_height)
	var/prev_height = height
	height = new_height
	if(abs(height - prev_height) > WATER_HEIGH_DIFFERENCE_DELTA_SPLASH)
		//Splash
		if(prob(WATER_HEIGH_DIFFERENCE_SOUND_CHANCE))
			var/sound_to_play = pick(list(
				'modular_zubbers/sound/effects/water_wade1.ogg',
				'modular_zubbers/sound/effects/water_wade2.ogg',
				'modular_zubbers/sound/effects/water_wade3.ogg',
				'modular_zubbers/sound/effects/water_wade4.ogg',
				))
			playsound(my_turf, sound_to_play, 60, 0)
		var/obj/splashy = new /obj/effect/temp_visual/liquid_splash(my_turf)
		splashy.color = color
		if(height >= LIQUID_WAIST_LEVEL_HEIGHT)
			//Push things into some direction, like space wind
			var/turf/dest_turf
			var/last_height = height
			for(var/turf in my_turf.atmos_adjacent_turfs)
				var/turf/T = turf
				if(T.z != my_turf.z)
					continue
				if(!T.liquids) //Automatic winner
					dest_turf = T
					break
				if(T.liquids.height < last_height)
					dest_turf = T
					last_height = T.liquids.height
			if(dest_turf)
				var/dir = get_dir(my_turf, dest_turf)
				var/atom/movable/AM
				for(var/thing in my_turf)
					AM = thing
					if(!AM.anchored && !AM.pulledby && !isobserver(AM) && (AM.move_resist < INFINITY))
						if(iscarbon(AM))
							var/mob/living/carbon/C = AM
							if(!(C.shoes && C.shoes.clothing_flags))
								step(C, dir)
								if(prob(60) && C.body_position != LYING_DOWN)
									to_chat(C, span_userdanger("The current knocks you down!"))
									C.Paralyze(60)
						else
							step(AM, dir)

/obj/effect/abstract/liquid_turf/immutable/set_height(new_height)
	height = new_height

/obj/effect/abstract/liquid_turf/proc/movable_entered(datum/source, atom/movable/AM)
	SIGNAL_HANDLER
	var/turf/T = source
	if(isobserver(AM))
		return //ghosts, camera eyes, etc. don't make water splashy splashy
	if(liquid_state >= LIQUID_STATE_ANKLES)
		if(prob(30))
			var/sound_to_play = pick(list(
				'modular_zubbers/sound/effects/water_wade1.ogg',
				'modular_zubbers/sound/effects/water_wade2.ogg',
				'modular_zubbers/sound/effects/water_wade3.ogg',
				'modular_zubbers/sound/effects/water_wade4.ogg',
				))
			playsound(T, sound_to_play, 50, 0)
		if(iscarbon(AM))
			var/mob/living/carbon/C = AM
			C.apply_status_effect(/datum/status_effect/water_affected)
	else if (isliving(AM))
		var/mob/living/L = AM
		if(prob(7) && !(L.movement_type & FLYING))
			L.slip(60, T, NO_SLIP_WHEN_WALKING, 20, TRUE)
	if(fire_state)
		AM.fire_act((T20C+50) + (50*fire_state), 125)

/obj/effect/abstract/liquid_turf/proc/mob_fall(datum/source, mob/M)
	SIGNAL_HANDLER
	var/turf/T = source
	if(liquid_state >= LIQUID_STATE_ANKLES && T.has_gravity(T))
		playsound(T, 'modular_zubbers/sound/effects/splash.ogg', 50, 0)
		if(iscarbon(M))
			var/mob/living/carbon/falling_carbon = M

			// No point in giving reagents to the deceased. It can cause some runtimes.
			if(falling_carbon.stat >= DEAD)
				return

			if(falling_carbon.wear_mask && falling_carbon.wear_mask.flags_cover & MASKCOVERSMOUTH)
				to_chat(falling_carbon, span_userdanger("You fall in the [reagents_to_text()]!"))
			else
				var/datum/reagents/tempr = take_reagents_flat(CHOKE_REAGENTS_INGEST_ON_FALL_AMOUNT)
				tempr.trans_to(falling_carbon, tempr.total_volume, methods = INGEST)
				qdel(tempr)
				falling_carbon.adjustOxyLoss(5)
				//C.emote("cough")
				INVOKE_ASYNC(falling_carbon, TYPE_PROC_REF(/mob, emote), "cough")
				to_chat(falling_carbon, span_userdanger("You fall in and swallow some [reagents_to_text()]!"))
		else
			to_chat(M, span_userdanger("You fall in the [reagents_to_text()]!"))

/obj/effect/abstract/liquid_turf/Initialize(mapload)
	. = ..()
	if(!SSliquids)
		CRASH("Liquid Turf created with the liquids sybsystem not yet initialized!")
	if(!immutable)
		my_turf = loc
		RegisterSignal(my_turf, COMSIG_ATOM_ENTERED, PROC_REF(movable_entered))
		RegisterSignal(my_turf, COMSIG_TURF_MOB_FALL, PROC_REF(mob_fall))
		RegisterSignal(my_turf, COMSIG_ATOM_EXAMINE, PROC_REF(examine_turf))
		SSliquids.add_active_turf(my_turf)

		SEND_SIGNAL(my_turf, COMSIG_TURF_LIQUIDS_CREATION, src)

	update_icon(UPDATE_OVERLAYS)
	if(z)
		QUEUE_SMOOTH(src)
		QUEUE_SMOOTH_NEIGHBORS(src)

	/* //Cant do it immediately, hmhm
	if(isspaceturf(my_turf))
		qdel(src, TRUE)
	*/

/obj/effect/abstract/liquid_turf/Destroy(force)
	if(force)
		UnregisterSignal(my_turf, list(COMSIG_ATOM_ENTERED, COMSIG_TURF_MOB_FALL, COMSIG_ATOM_EXAMINE))
		if(my_turf.lgroup)
			my_turf.lgroup.remove_from_group(my_turf)
		if(SSliquids.evaporation_queue[my_turf])
			SSliquids.evaporation_queue -= my_turf
		if(SSliquids.processing_fire[my_turf])
			SSliquids.processing_fire -= my_turf
		//Is added because it could invoke a change to neighboring liquids
		SSliquids.add_active_turf(my_turf)
		my_turf.liquids = null
		my_turf = null
		QUEUE_SMOOTH_NEIGHBORS(src)
	else
		return QDEL_HINT_LETMELIVE
	return ..()

/obj/effect/abstract/liquid_turf/immutable/Destroy(force)
	if(force)
		stack_trace("Something tried to hard destroy an immutable liquid.")
	return ..()

//Exposes my turf with simulated reagents
/obj/effect/abstract/liquid_turf/proc/ExposeMyTurf()
	var/datum/reagents/tempr = simulate_reagents_threshold(LIQUID_REAGENT_THRESHOLD_TURF_EXPOSURE)
	tempr.expose(my_turf, TOUCH, tempr.total_volume)
	qdel(tempr)

/obj/effect/abstract/liquid_turf/proc/ChangeToNewTurf(turf/NewT)
	if(NewT.liquids)
		stack_trace("Liquids tried to change to a new turf, that already had liquids on it!")

	UnregisterSignal(my_turf, list(COMSIG_ATOM_ENTERED, COMSIG_TURF_MOB_FALL))
	if(SSliquids.active_turfs[my_turf])
		SSliquids.active_turfs -= my_turf
		SSliquids.active_turfs[NewT] = TRUE
	if(SSliquids.evaporation_queue[my_turf])
		SSliquids.evaporation_queue -= my_turf
		SSliquids.evaporation_queue[NewT] = TRUE
	if(SSliquids.processing_fire[my_turf])
		SSliquids.processing_fire -= my_turf
		SSliquids.processing_fire[NewT] = TRUE
	my_turf.liquids = null
	my_turf = NewT
	NewT.liquids = src
	loc = NewT
	RegisterSignal(my_turf, COMSIG_ATOM_ENTERED, PROC_REF(movable_entered))
	RegisterSignal(my_turf, COMSIG_TURF_MOB_FALL, PROC_REF(mob_fall))

/**
 * Handles COMSIG_ATOM_EXAMINE for the turf.
 *
 * Adds reagent info to examine text.
 * Arguments:
 * * source - the turf we're peekin at
 * * examiner - the user
 * * examine_text - the examine list
 *  */
/obj/effect/abstract/liquid_turf/proc/examine_turf(turf/source, mob/examiner, list/examine_list)
	SIGNAL_HANDLER

	// This should always have reagents if this effect object exists, but as a sanity check...
	if(!length(reagent_list))
		return

	var/liquid_state_template = liquid_state_messages["[liquid_state]"]

	examine_list += EXAMINE_SECTION_BREAK

	if(examiner.can_see_reagents())
		examine_list += EXAMINE_SECTION_BREAK

		if(length(reagent_list) == 1)
			// Single reagent text.
			var/datum/reagent/reagent_type = reagent_list[1]
			var/reagent_name = initial(reagent_type.name)
			var/volume = round(reagent_list[reagent_type], 0.01)

			examine_list += span_notice("There is [replacetext(liquid_state_template, "$", "[volume] units of [reagent_name]")] here.")
		else
			// Show each individual reagent
			examine_list += "There is [replacetext(liquid_state_template, "$", "the following")] here:"

			for(var/datum/reagent/reagent_type as anything in reagent_list)
				var/reagent_name = initial(reagent_type.name)
				var/volume = round(reagent_list[reagent_type], 0.01)
				examine_list += "&bull; [volume] units of [reagent_name]"

		examine_list += span_notice("The solution has a temperature of [temp]K.")
		examine_list += EXAMINE_SECTION_BREAK
		return

	// Otherwise, just show the total volume
	examine_list += span_notice("There is [replacetext(liquid_state_template, "$", "liquid")] here.")

/**
 * Creates a string of the reagents that make up this liquid.
 *
 * Puts the reagent(s) that make up the liquid into string form e.g. "plasma" or "plasma and water", or 'plasma, milk, and water' depending on how many reagents there are.
 *
 * Returns the reagents list string or a generic "liquid" if there are no reagents somehow
 *  */
/obj/effect/abstract/liquid_turf/proc/reagents_to_text()
	/// the total amount of different types of reagents in the liquid
	var/total_reagents = length(reagent_list)
	/// the amount of different types of reagents that have not been listed yet
	var/reagents_remaining = total_reagents
	/// the final string to be returned
	var/reagents_string = ""
	if(!reagents_remaining)
		return reagents_string += "liquid"

	do
		for(var/datum/reagent/reagent_type as anything in reagent_list)
			reagents_string += "[initial(reagent_type.name)]"
			reagents_remaining--
			if(!reagents_remaining)
				break
			// if we are at the last reagent in the list, preface its name with 'and'.
			// do not use a comma if there were only two reagents in the list
			if(total_reagents == 2)
				reagents_string += " and "
			else
				reagents_string += ", "
				if(reagents_remaining == 1)
					reagents_string += "and "
	while(reagents_remaining)

	return LOWER_TEXT(reagents_string)

/obj/effect/temp_visual/liquid_splash
	icon = 'modular_skyrat/modules/liquids/icons/obj/effects/splash.dmi'
	icon_state = "splash"
	layer = FLY_LAYER
	randomdir = FALSE

/obj/effect/abstract/liquid_turf/immutable
	immutable = TRUE
	var/list/starting_mixture = list(/datum/reagent/water = 600)
	var/starting_temp = T20C

//STRICTLY FOR IMMUTABLES DESPITE NOT BEING /immutable
/obj/effect/abstract/liquid_turf/proc/add_turf(turf/T)
	T.liquids = src
	T.vis_contents += src
	SSliquids.active_immutables[T] = TRUE
	RegisterSignal(T, COMSIG_ATOM_ENTERED, PROC_REF(movable_entered))
	RegisterSignal(T, COMSIG_TURF_MOB_FALL, PROC_REF(mob_fall))

/obj/effect/abstract/liquid_turf/proc/remove_turf(turf/T)
	SSliquids.active_immutables -= T
	T.liquids = null
	T.vis_contents -= src
	UnregisterSignal(T, list(COMSIG_ATOM_ENTERED, COMSIG_TURF_MOB_FALL))

/obj/effect/abstract/liquid_turf/immutable/ocean
	smoothing_flags = NONE
	icon_state = "ocean"
	base_icon_state = "ocean"
	layer = FLY_LAYER
	plane = ABOVE_GAME_PLANE
	starting_temp = T20C-150
	no_effects = TRUE
	vis_flags = NONE

/obj/effect/abstract/liquid_turf/immutable/ocean/warm
	starting_temp = T20C+20

/obj/effect/abstract/liquid_turf/immutable/Initialize(mapload, plane_offset)
	. = ..()
	SET_PLANE_W_SCALAR(src, initial(plane), plane_offset)
	reagent_list = starting_mixture.Copy()
	total_reagents = 0
	for(var/key in reagent_list)
		total_reagents += reagent_list[key]
	temp = starting_temp
	calculate_height()
	set_reagent_color_for_liquid()
