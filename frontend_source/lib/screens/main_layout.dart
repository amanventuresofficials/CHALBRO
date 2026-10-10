import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../utils/app_colors.dart';
import '../utils/language_provider.dart';
import 'home_screen.dart';
import 'post_task_screen.dart';
import 'my_tasks_screen.dart';
import 'profile_screen.dart';
import 'find_work_screen.dart';
import 'find_helpers_screen.dart';
import '../services/notification_service.dart';
import '../services/hired_contacts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;
  final DatabaseService _dbService = DatabaseService();
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _dbService.cleanupExpiredTasks();
    NotificationService().init();
    HiredContacts.instance.start();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final hasInternet = !results.contains(ConnectivityResult.none);
      if (!hasInternet && mounted) {
        final s = context.read<LanguageProvider>().strings;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.noInternetMessage),
            backgroundColor: AppColors.red,
            duration: const Duration(days: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (hasInternet && mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  List<Widget> _getScreens() {
    return [
      HomeScreen(onNavigate: (index) => setState(() => _currentIndex = index)),
      const PostTaskScreen(),
      const FindHelpersScreen(),
      const FindWorkScreen(),
      const MyTasksScreen(),
      const ProfileScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _dbService.streamUserData(),
      builder: (context, userSnapshot) {
        String userCity = "Surat";
        if (userSnapshot.hasData && userSnapshot.data!.exists) {
          userCity =
              (userSnapshot.data!.data() as Map<String, dynamic>)['city'] ??
                  "Surat";
        }

        return StreamBuilder<QuerySnapshot>(
          stream: _dbService.streamAvailableCityTasks(userCity),
          builder: (context, taskSnapshot) {

          if (taskSnapshot.hasData) {
              // Task data available but count not displayed in nav yet
            }

            // Count open-for-work helpers (for badge on Find Workers tab)
            return StreamBuilder<QuerySnapshot>(
              stream: _dbService.streamAvailableHelpers(userCity),
              builder: (context, helpersSnapshot) {
                int helpersCount = 0;
                if (helpersSnapshot.hasData) {
                  final currentUid = FirebaseAuth.instance.currentUser?.uid;
                  helpersCount = helpersSnapshot.data!.docs
                      .where((doc) =>
                          (doc.data() as Map<String, dynamic>)['uid'] !=
                          currentUid)
                      .length;
                }

                return Scaffold(
                  backgroundColor: AppColors.background,
                  body: IndexedStack(
                    index: _currentIndex,
                    children: _getScreens(),
                  ),
                  bottomNavigationBar: BottomNavigationBar(
                    backgroundColor: Colors.white,
                    currentIndex: _currentIndex,
                    onTap: (index) => setState(() => _currentIndex = index),
                    type: BottomNavigationBarType.fixed,
                    selectedItemColor: AppColors.primary,
                    unselectedItemColor: AppColors.greyText,
                    showUnselectedLabels: true,
                    selectedLabelStyle:
                        const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                    unselectedLabelStyle:
                        const TextStyle(fontWeight: FontWeight.w500, fontSize: 10),
                    items: [
                      BottomNavigationBarItem(
                          icon: const Icon(Icons.home_outlined),
                          activeIcon: const Icon(Icons.home),
                          label: context.watch<LanguageProvider>().strings.navHome),
                      BottomNavigationBarItem(
                          icon: const Icon(Icons.edit_outlined),
                          activeIcon: const Icon(Icons.edit),
                          label: context.watch<LanguageProvider>().strings.navPostTask),
                      BottomNavigationBarItem(
                          icon: Badge(
                            isLabelVisible: helpersCount > 0,
                            label: Text(helpersCount.toString()),
                            child: const Icon(Icons.people_outline),
                          ),
                          activeIcon: Badge(
                            isLabelVisible: helpersCount > 0,
                            label: Text(helpersCount.toString()),
                            child: const Icon(Icons.people),
                          ),
                          label: context.watch<LanguageProvider>().strings.navFindHelp),
                      BottomNavigationBarItem(
                          icon: Badge(
                            isLabelVisible: true,
                            label: const Text('NEW', style: TextStyle(fontSize: 8)),
                            backgroundColor: AppColors.red,
                            child: const Icon(Icons.location_on_outlined),
                          ),
                          activeIcon: Badge(
                            isLabelVisible: true,
                            label: const Text('NEW', style: TextStyle(fontSize: 8)),
                            backgroundColor: AppColors.red,
                            child: const Icon(Icons.location_on),
                          ),
                          label: context.watch<LanguageProvider>().strings.navNearby),
                      BottomNavigationBarItem(
                          icon: const Icon(Icons.check_circle_outline),
                          activeIcon: const Icon(Icons.check_circle),
                          label: context.watch<LanguageProvider>().strings.navTasks),
                      BottomNavigationBarItem(
                          icon: const Icon(Icons.person_outline),
                          activeIcon: const Icon(Icons.person),
                          label: context.watch<LanguageProvider>().strings.navProfile),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
