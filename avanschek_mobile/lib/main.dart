import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const AvanschekApp());
}

class AvanschekApp extends StatelessWidget {
  const AvanschekApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Авансовый отчёт АО-1',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue.shade800),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
