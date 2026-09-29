class TaskModel {
  final String id;
  final String title;
  final String description;
  final String price;
  final String distance;
  final bool isUrgent;
  final String status;

  TaskModel({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.distance,
    this.isUrgent = false,
    this.status = 'open', // CHANGED from 'Pending'
  });
}

class HelperModel {
  final String id;
  final String name;
  final String role;
  final double rating;
  final int reviews;
  final String price;
  final String distance;
  final bool isAvailable;

  HelperModel({
    required this.id,
    required this.name,
    required this.role,
    required this.rating,
    required this.reviews,
    required this.price,
    required this.distance,
    this.isAvailable = true,
  });
}
