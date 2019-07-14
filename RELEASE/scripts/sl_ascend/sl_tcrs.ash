script "sl_tcrs.ash"

boolean in_tcrs()
{
	return my_path() == "36" || my_path() == "Two Crazy Random Summer";
}

boolean tcrs_initializeSettings()
{
	if(in_tcrs())
	{
		set_property("sl_spookyfertilizer", "");
		set_property("sl_getStarKey", true);
		set_property("sl_holeinthesky", true);
		set_property("sl_wandOfNagamar", true);
	}
	return true;
}

boolean[int] knapsack(int maxw, int n, int[int] weight, float[int] val)
{
	/*
	 * standard implementation of 0-1 Knapsack problem with dynamic programming
	 * Time complexity: O(maxw * n)
	 * For 16k items on a 2017 laptop, took about 5 seconds and 60Mb of RAM
	 *
	 * Parameters:
	 *   maxw is the desired sum-of-weights (e.g. fullness_left())
	 *   n is the number of elements
	 *   weight is the (e.g. a map from i=1..n => fullness of i-th food)
	 *   val is the value to maximize (e.g. a map from i=1..n => adventures of i-th food)
	 * Returns: a set of indices that were taken
	 */

	if(n*maxw >= 100000)
	{
		print("Solving a Knapsack instance with " + n + " elements and " + maxw + " total weight, this might be slow and memory-intensive.");
	}

	/* V[i][w] is "with only the first i items, what is the maximum
	 * sum-of-vals we can generate with total weight w?
	 */
	float [int][int] V;

	for (int i = 0; i <= n; i++)
	{
		for (int w = 0; w <= maxw; w++)
		{
			if (i==0 || w==0) 
				V[i][w] = 0; 
			else if (weight[i-1] <= w) 
				V[i][w] = max(val[i-1] + V[i-1][w-weight[i-1]], V[i-1][w]);
			else
				V[i][w] = V[i-1][w];
		}
	}

	boolean[int] ret;
	// backtrack
	int i = n;
	int w = maxw;
	while (i > 0 || w > 0)
	{
		// Did this item change our mind about how many adventures we could generate?
		// If so, we took this item.
		if (V[i][w] != V[i-1][w])
		{
			w -= weight[i-1];
			ret[i-1] = true;
		}
		else
		{
			// do not take element
			i -= 1;
		}
	}
	// This can be somewhat memory-intensive.
	// I'm not sure if this actually does anything, but it makes me feel better.
	cli_execute("gc");
	return ret;
}

boolean can_simultaneously_acquire(int[item] needed)
{
	// The Knapsack solver can provide invalid solutions - for example, if we
	// have 2 perfect ice cubes and 6 organ space, it might suggest two distinct
	// perfect drinks.
	// Checks that a set of items isn't impossible to acquire because of
	// conflicting crafting dependencies.

	int[item] alreadyUsed;

	boolean failed = false;
	void addToAlreadyUsed(int amount, item toAdd)
	{
		int needToCraft = alreadyUsed[toAdd] + amount - item_amount(toAdd);
		alreadyUsed[toAdd] += amount;
		if(needToCraft > 0)
		{
			if (count(get_ingredients(toAdd)) == 0)
			{
				// not craftable
				failed = true;
			}

			foreach ing,ingAmount in get_ingredients(toAdd)
			{
				addToAlreadyUsed(ingAmount * needToCraft, ing);
			}
		}
	}

	foreach it, amt in needed
	{
		addToAlreadyUsed(amt, it);
	}

	return !failed;
}

boolean tcrs_loadCafeDrinks(int[int] cafe_backmap, float[int] adv, int[int] inebriety)
{
	if(!in_tcrs()) return false;

	record _CAFE_DRINK_TYPE {
		string name;
		int inebriety;
		string quality;
	};

	_CAFE_DRINK_TYPE [int] cafe_booze;
	string filename = "TCRS_" + my_class().to_string().replace_string(" ", "_") + "_" + my_sign() + "_cafe_booze.txt";
	print("Loading " + filename, "blue");
	file_to_map(filename, cafe_booze);
	foreach i, r in cafe_booze
	{
		// Gnomish Microbrewery has item ids -1, -2, -3
		if (i >= -3 && r.inebriety > 0)
		{
			int limit = min(my_meat()/100, inebriety_left()/r.inebriety);
			for (int j=0; j<limit; j++)
			{
				int n = count(inebriety);
				inebriety[n] = r.inebriety;
				adv[n] = r.inebriety * tcrs_expectedAdvPerFill(r.quality);
				cafe_backmap[n] = i;
			}
		}
	}
	return true;
}

boolean sl_knapsackAutoEat()
{
	// TODO: Doesn't yet use Canadian cafe food.

	if(fullness_left() == 0) return false;

	int[int] fullness;
	float[int] adv;
	item[int] item_backmap;

	foreach it in $items[]
	{
		if ((it.quality == "awesome" || it.quality == "EPIC") && canEat(it) && (it.fullness > 0) && is_unrestricted(it) && historical_price(it) <= 20000)
		{
			int amount = available_amount(it) + creatable_amount(it);
			if (npc_price(it) > 0) amount += my_meat() / npc_price(it);
			int limit = min(amount, fullness_left()/it.fullness);
			for (int i=0; i<limit; i++)
			{
				int n = count(fullness);
				fullness[n] = it.fullness;
				adv[n] = expectedAdventuresFrom(it);
				item_backmap[n] = it;
			}
		}
	}
	int[item] foods;
	foreach i in knapsack(fullness_left(), count(fullness), fullness, adv)
	{
		foods[item_backmap[i]] += 1;
	}
	if(!can_simultaneously_acquire(foods))
	{
		print("Considering eating: ", "red");
		foreach it, amt in foods
		{
			print(it + ":" + amt, "red");
		}
		print("I'm a little confused about what to eat. I'll wait and see if I get unconfused - otherwise, please eat manually.", "red");
		return false;
	}
	if (count(foods) > 0)
	{
		foreach what, howmany in foods
		{
			retrieve_item(howmany, what);
		}
		if (in_tcrs() && get_property("sl_useWishes").to_boolean() && (0 == have_effect($effect[Got Milk])))
		{
			// +15 adv is worth it for daycount
			// TODO: Some folks have requested a setting to turn this off.
			makeGenieWish($effect[Got Milk]);
		}
		else dealwithMilkOfMagnesium(true);

		foreach what, howmany in foods
		{
			slEat(howmany, what);
		}
		return true;
	}
	return false;
}

boolean loadDrinks(item[int] item_backmap, float[int] adv, int[int] inebriety)
{
	foreach it in $items[]
	{
		// TODO: Maybe relax the "awesome or EPIC" standard outside of TCRS? I hear Standard is rough.
		if ((it.quality == "awesome" || it.quality == "EPIC") && canDrink(it) && (it.inebriety > 0) && is_unrestricted(it) && historical_price(it) <= 20000)
		{
			int amount = available_amount(it) + creatable_amount(it);
			if (npc_price(it) > 0) amount += my_meat() / npc_price(it);
			int limit = min(amount, inebriety_left()/it.inebriety);
			for (int i=0; i<limit; i++)
			{
				int n = count(inebriety);
				inebriety[n] = it.inebriety;
				adv[n] = expectedAdventuresFrom(it);
				item_backmap[n] = it;
			}
		}
	}
	return true;
}

boolean sl_knapsackAutoDrink()
{
	if (inebriety_left() == 0) return false;

	int[int] inebriety;
	float[int] adv;
	item[int] item_backmap;
	loadDrinks(item_backmap, adv, inebriety);

	int [int] cafe_backmap;
	tcrs_loadCafeDrinks(cafe_backmap, adv, inebriety);

	int[item] normal_drinks;
	int[int] cafe_drinks;

	boolean[int] result = knapsack(inebriety_left(), count(inebriety), inebriety, adv);
	foreach i in result
	{
		if (cafe_backmap contains i)
		{
			cafe_drinks[cafe_backmap[i]] += 1;
		}
		else
		{
			normal_drinks[item_backmap[i]] += 1;
		}
	}
	if(!can_simultaneously_acquire(normal_drinks))
	{
		print("Considering drinking:", "red");
		foreach it, amt in normal_drinks
		{
			print(it + ":" + amt, "red");
		}
		print("It looks like I can't simultaneously get everything that I want to drink. I'll wait and see if I get unconfused - otherwise, please drink manually.", "red");
		return false;
	}

	if (count(normal_drinks) > 0)
	{
		foreach what, howmany in normal_drinks
		{
			retrieve_item(howmany, what);
		}

		foreach what, howmany in normal_drinks
		{
			print("TODO: would drink "+ howmany + " of " + what);
			// slDrink(howmany, what);
		}
		return true;
	}
	foreach what, howmany in cafe_drinks
	{
		buffMaintain($effect[Ode to Booze], 20, 1, inebriety_left());
		slDrinkCafe(howmany, what);
	}
	return false;
}

boolean sl_autoDrinkOne()
{
	if (inebriety_left() == 0) return false;

	int[int] inebriety;
	float[int] adv;
	item[int] item_backmap;
	loadDrinks(item_backmap, adv, inebriety);

	int [int] cafe_backmap;
	tcrs_loadCafeDrinks(cafe_backmap, adv, inebriety);

	int[item] normal_drinks;
	int[int] cafe_drinks;

	float best_adv_per_drunk = 0.0;
	int best_index = -1;
	int n = count(inebriety);
	for (int i=0; i<n; i++)
	{
		float tentative_adv_per_drunk = adv[i]/inebriety[i];
		if (tentative_adv_per_drunk > best_adv_per_drunk)
		{
			best_adv_per_drunk = tentative_adv_per_drunk;
			best_index = i;
		}
	}

	if (cafe_backmap contains best_index)
	{
		buffMaintain($effect[Ode to Booze], 20, 1, inebriety[best_index]);
		return slDrinkCafe(1, cafe_backmap[best_index]); // Scrawny Stout;
	}
	else
	{
		return slDrink(1, item_backmap[best_index]);
	}
}

boolean tcrs_consumption()
{
	if(!in_tcrs())
		return false;

	if(sl_beta() && my_adventures() < 10)
	{
		if(my_inebriety() < 8 && inebriety_left() > 0)
		{
			// just drink, like, anything, whatever
			// find the best and biggest thing we can and drink it
			return sl_autoDrinkOne();
		}
		if(inebriety_left() > 0)
		{
			if (sl_knapsackAutoDrink()) return true;
		}
		if(fullness_left() > 0)
		{
			if (sl_knapsackAutoEat()) return true;
		}
	}

	if(my_class() == $class[Sauceror] && my_sign() == "Blender")
	{
		boolean canDesert = (get_property("lastDesertUnlock").to_int() == my_ascensions());
		if((inebriety_left() >= 4) && canDesert && (my_meat() >= 75))
		{
			buffMaintain($effect[Ode to Booze], 20, 1, 4);
			slDrinkCafe(1, -2); // Scrawny Stout;
		}
		if((my_adventures() <= 1) && (inebriety_left() == 3) && (my_meat() >= npc_price($item[used beer])))
		{
			buyUpTo(1, $item[used beer]);
			slDrink(1, $item[used beer]);
		}
		if((my_adventures() <= 1 || item_amount($item[glass of goat's milk]) > 0) && fullness_left() == 15)
		{
			if(get_property("sl_useWishes").to_boolean() && (0 == have_effect($effect[Got Milk])))
			{
				makeGenieWish($effect[Got Milk]); // +15 adv is worth it for daycount
			}
			buy(1, $item[fortune cookie]);
			buy(6, $item[pickled egg]);
			slEat(1, $item[fortune cookie]);
			slEat(6, $item[pickled egg]);
			if(item_amount($item[glass of goat's milk]) > 0)
			{
				slEat(1, $item[glass of goat's milk]);
			}
			else	 // 1 adventure left, better than wasting the Milk charge?
			{
				acquireHermitItem($item[Ketchup]);
				slEat(1, $item[Ketchup]);
			}
		}
	}
	else
	{
		print("Not eating or drinking anything, since we don't know what's good...");
	}
	return true;
}

boolean tcrs_maximize_with_items(string maximizerString)
{
	if (!in_tcrs()) return false;

	/* In TCRS, items give random effects. Instead of hard-coding a list of
	 * effects for each path/class combination, we look at what we got.
	 */
	boolean used_anything = false;
	foreach i, rec in maximize(maximizerString, 300, 0, true, false)
	{
		if((rec.item != $item[none])
		&& (rec.item.fullness == 0)
		&& (rec.item.inebriety == 0)
		&& (0 == have_effect(rec.effect))
		&& (mall_price(rec.item) <= 300)
		&& (rec.score > 0.1)) // sometimes maximizer gives spurious results
		{
			cli_execute(rec.command);
			used_anything = true;
		}
	}
	return used_anything;
}
