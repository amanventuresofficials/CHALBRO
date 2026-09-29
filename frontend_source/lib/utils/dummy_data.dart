import '../models/app_models.dart';

class DummyData {
  static List<TaskModel> urgentTasks = [
    TaskModel(
        id: '1',
        title: 'Need Driver Now',
        description: 'Surat Airport to Navsari',
        price: '₹800',
        distance: '2 km',
        isUrgent: true),
    TaskModel(
        id: '2',
        title: 'Need Electrician',
        description: 'Fix wiring issue',
        price: '₹500',
        distance: '1.5 km',
        isUrgent: true),
  ];

  static List<HelperModel> helpers = [
    HelperModel(
        id: '1',
        name: 'Raj',
        role: 'Driver',
        rating: 4.8,
        reviews: 120,
        price: '₹15/km',
        distance: '2 km',
        isAvailable: true),
    HelperModel(
        id: '2',
        name: 'Neha',
        role: 'Tutor',
        rating: 4.9,
        reviews: 85,
        price: '₹500/hr',
        distance: '1.8 km',
        isAvailable: true),
    HelperModel(
        id: '3',
        name: 'Amit',
        role: 'Electrician',
        rating: 4.7,
        reviews: 60,
        price: '₹700',
        distance: '2.5 km',
        isAvailable: true),
  ];

  static List<Map<String, dynamic>> categories = [
    {'icon': '🚗', 'label': 'Transport'},
    {'icon': '🏠', 'label': 'Home Svcs'},
    {'icon': '📚', 'label': 'Education'},
    {'icon': '🎉', 'label': 'Events'},
    {'icon': '🔧', 'label': 'Tech & Repair'},
    {'icon': '💪', 'label': 'Daily Help'},
    {'icon': '⚽', 'label': 'Sports'},
    {'icon': '✈️', 'label': 'Travel'},
  ];
}
