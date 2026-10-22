import 'package:flutter/material.dart';

/// User-selectable icons. Persisted by index so icon fonts stay tree-shakable.
/// Only append to this list — never reorder.
const kIconSet = <IconData>[
  Icons.restaurant_rounded, // 0 food
  Icons.directions_car_rounded, // 1 transport
  Icons.shopping_bag_rounded, // 2 shopping
  Icons.receipt_long_rounded, // 3 bills
  Icons.movie_rounded, // 4 entertainment
  Icons.favorite_rounded, // 5 health
  Icons.school_rounded, // 6 education
  Icons.fitness_center_rounded, // 7 gym
  Icons.category_rounded, // 8 other
  Icons.payments_rounded, // 9 salary
  Icons.work_rounded, // 10 freelance
  Icons.card_giftcard_rounded, // 11 gift
  Icons.trending_up_rounded, // 12 investment
  Icons.home_rounded, // 13 rent
  Icons.subscriptions_rounded, // 14 subscriptions
  Icons.local_cafe_rounded, // 15
  Icons.water_drop_rounded, // 16
  Icons.self_improvement_rounded, // 17
  Icons.directions_run_rounded, // 18
  Icons.bedtime_rounded, // 19
  Icons.menu_book_rounded, // 20
  Icons.code_rounded, // 21
  Icons.no_food_rounded, // 22
  Icons.smoke_free_rounded, // 23
  Icons.spa_rounded, // 24
  Icons.brush_rounded, // 25
  Icons.music_note_rounded, // 26
  Icons.language_rounded, // 27
  Icons.savings_rounded, // 28
  Icons.pets_rounded, // 29
  Icons.phone_iphone_rounded, // 30
  Icons.flight_rounded, // 31
  Icons.local_grocery_store_rounded, // 32
  Icons.wb_sunny_rounded, // 33
  Icons.cleaning_services_rounded, // 34
  Icons.psychology_rounded, // 35
];

IconData iconAt(int i) => kIconSet[(i >= 0 && i < kIconSet.length) ? i : 8];
