/*
/datum/vote
	/// The threshold for a winner in ranked voting as a percentage (0-100)
	var/ranked_winner_threshold = 50

/// Gets the winner using ranked choice voting.
/datum/vote/proc/get_ranked_winner()
	// Total number of voters who submitted at least one ranked choice
	var/total_voters = 0
	// List of all voter ckeys
	var/list/all_voters = list()

	// Collect all voters and create a map of their current rankings
	var/list/voter_rankings = list() // Stores current rankings for each voter
	for(var/key in choices_by_ckey)
		var/split_key = splittext(key, "_")
		if(length(split_key) != 2)
			continue

		var/ckey = split_key[1]
		var/choice = split_key[2]
		var/rank = choices_by_ckey[key]

		if(rank > 0)
			if(!(ckey in all_voters))
				all_voters += ckey
				total_voters++
				voter_rankings[ckey] = list()

			voter_rankings[ckey][choice] = rank

	// Log initial state
	var/initial_state_text = "Ranked Vote Initial State:\nTotal Voters: [total_voters]\nCurrent Choices:\n"
	var/list/initial_state_data = list(
		"total_voters" = total_voters,
		"choices" = list()
	)
	for(var/choice in choices)
		initial_state_text += "\t[choice]: [choices[choice]] votes\n"
		initial_state_data["choices"][choice] = choices[choice]

	initial_state_text += "\nVoter Rankings:\n"
	initial_state_data["voter_rankings"] = list()
	for(var/ckey in voter_rankings)
		initial_state_text += "\t[ckey]'s rankings:\n\t\t"
		var/list/sorted_rankings = list()
		var/list/rankings = voter_rankings[ckey]
		initial_state_data["voter_rankings"][ckey] = length(rankings) ? rankings.Copy() : null
		for(var/i in 1 to length(rankings))
			for(var/choice in rankings)
				if(rankings[choice] == i)
					sorted_rankings += "[i]. [choice]"
		initial_state_text += sorted_rankings.Join(", ") + "\n"

	log_vote(initial_state_text, initial_state_data)

	// If no one voted, return empty list
	if(total_voters == 0)
		return list()

	// Calculate the threshold for victory
	var/victory_threshold = round((total_voters * ranked_winner_threshold) / 100, 1)
	log_vote("Victory threshold set to [victory_threshold] votes ([ranked_winner_threshold]% of [total_voters] voters)",
		list("threshold" = victory_threshold, "threshold_percent" = ranked_winner_threshold, "total_voters" = total_voters))

	var/round_number = 1
	// While we still have choices to consider
	while(length(choices) > 1)
		log_vote("=== Round [round_number] of Ranked Choice Voting ===", list("round" = round_number))

		// Find highest vote count and check if it meets threshold
		var/highest_votes = 0
		var/list/highest_choices = list()

		for(var/option in choices)
			var/votes = choices[option]
			if(votes > highest_votes)
				highest_votes = votes
				highest_choices = list(option)
			else if(votes == highest_votes)
				highest_choices += option

		// Check if any option has reached the threshold
		if(highest_votes >= victory_threshold)
			log_vote("Victory threshold ([victory_threshold]) reached! Winner(s): [highest_choices.Join(", ")] with [highest_votes] votes",
				list("winners" = highest_choices, "votes" = highest_votes))
			return highest_choices

		// Find lowest vote count to eliminate
		var/lowest_votes = INFINITY
		var/list/lowest_choices = list()

		for(var/option in choices)
			var/votes = choices[option]
			if(votes < lowest_votes)
				lowest_votes = votes
				lowest_choices = list(option)
			else if(votes == lowest_votes)
				lowest_choices += option

		// If we have multiple options with the lowest votes, pick one randomly
		var/option_to_eliminate
		if(length(lowest_choices) > 1)
			option_to_eliminate = pick(lowest_choices)
			log_vote("Multiple options tied for lowest votes ([lowest_votes]): [lowest_choices.Join(", ")]. Randomly eliminating: [option_to_eliminate]",
				list("tied_options" = lowest_choices, "eliminated" = option_to_eliminate, "votes" = lowest_votes))
		else
			option_to_eliminate = lowest_choices[1]
			log_vote("Eliminating [option_to_eliminate] with lowest votes: [lowest_votes]",
				list("eliminated" = option_to_eliminate, "votes" = lowest_votes))

		// Remove the eliminated option from choices
		choices -= option_to_eliminate

		// Update rankings and redistribute votes
		var/redistribution_text = "Vote redistribution after eliminating [option_to_eliminate]:\n"
		var/list/redistribution_data = list(
			"eliminated" = option_to_eliminate,
			"redistributions" = list()
		)

		for(var/ckey in voter_rankings)
			var/list/rankings = voter_rankings[ckey]
			var/eliminated_rank = rankings[option_to_eliminate]
			if(!eliminated_rank)
				continue

			// Remove the eliminated option from their rankings
			rankings -= option_to_eliminate

			// If it was their first choice, we need to redistribute their vote
			if(eliminated_rank == 1)
				// Find their new first choice
				var/new_first_choice
				var/lowest_rank = INFINITY
				for(var/choice in rankings)
					var/rank = rankings[choice]
					if(rank < lowest_rank)
						lowest_rank = rank
						new_first_choice = choice

				// Redistribute the vote if they have another choice
				if(new_first_choice)
					redistribution_text += "\t[ckey]'s vote moved from [option_to_eliminate] to [new_first_choice]\n"
					redistribution_data["redistributions"] += list(list(
						"voter" = ckey,
						"from" = option_to_eliminate,
						"to" = new_first_choice
					))
					choices[new_first_choice]++

				// Adjust all remaining ranks down by 1
				for(var/choice in rankings)
					rankings[choice]--

			// Update the choices_by_ckey list to reflect the new rankings
			for(var/choice in rankings)
				choices_by_ckey["[ckey]_[choice]"] = rankings[choice]

		log_vote(redistribution_text, redistribution_data)

		// Log current state of choices and rankings
		var/status_text = "Current vote counts after round [round_number]:\n"
		var/list/status_data = list(
			"round" = round_number,
			"choices" = list(),
			"rankings" = list()
		)

		for(var/option in choices)
			status_text += "\t[option]: [choices[option]] votes\n"
			status_data["choices"][option] = choices[option]

		status_text += "\nUpdated Rankings:\n"
		for(var/ckey in voter_rankings)
			status_text += "\t[ckey]'s rankings:\n\t\t"
			var/list/sorted_rankings = list()
			var/list/rankings = voter_rankings[ckey]
			status_data["rankings"][ckey] = length(rankings) ? rankings.Copy() : null
			for(var/i in 1 to length(rankings))
				for(var/choice in rankings)
					if(rankings[choice] == i)
						sorted_rankings += "[i]. [choice]"
			status_text += sorted_rankings.Join(", ") + "\n"

		log_vote(status_text, status_data)

		round_number++

	// If we're down to one option, it's the winner
	if(length(choices) == 1)
		log_vote("Only one option remains: [choices[1]] is the winner!", list("winner" = choices[1]))
		return list(choices[1])

	// This should never happen but just in case
	log_vote("ERROR: Ranked choice voting ended with no winner!", list())
	return list()
*/
