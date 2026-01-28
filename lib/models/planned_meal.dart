enum MealType { breakfast, lunch, dinner }

MealType mealTypeFromString(String value) {
  switch (value) {
    case 'breakfast':
      return MealType.breakfast;
    case 'lunch':
      return MealType.lunch;
    case 'dinner':
      return MealType.dinner;
    default:
      throw ArgumentError('Unknown mealType: $value');
  }
}

String mealTypeToString(MealType mealType) {
  switch (mealType) {
    case MealType.breakfast:
      return 'breakfast';
    case MealType.lunch:
      return 'lunch';
    case MealType.dinner:
      return 'dinner';
  }
}

class PlannedMeal {
  final int dayIndex; // 0..6
  final MealType mealType;
  final int recipeId;

  const PlannedMeal({
    required this.dayIndex,
    required this.mealType,
    required this.recipeId,
  });

  Map<String, dynamic> toJson() => {
        'dayIndex': dayIndex,
        'mealType': mealTypeToString(mealType),
        'recipeId': recipeId,
      };

  factory PlannedMeal.fromJson(Map<String, dynamic> json) {
    return PlannedMeal(
      dayIndex: (json['dayIndex'] as num).toInt(),
      mealType: mealTypeFromString(json['mealType'] as String),
      recipeId: (json['recipeId'] as num).toInt(),
    );
  }
}
