import 'package:flutter/material.dart';

import 'almuerzos_rrhh_screen.dart';
import 'avisos_rrhh_screen.dart';
import 'empleados_rrhh_screen.dart';
import 'reportes_rrhh_screen.dart';

class NavRRHHScreen extends StatefulWidget {
  const NavRRHHScreen({super.key, this.userData});

  final Map<String, dynamic>? userData;

  @override
  State<NavRRHHScreen> createState() => _NavRRHHScreenState();
}

class _NavRRHHScreenState extends State<NavRRHHScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final paginas = [
      ReportesRRHHScreen(userData: widget.userData),
      AlmuerzosRRHHScreen(userData: widget.userData),
      AvisosRRHHScreen(userData: widget.userData),
      EmpleadosRRHHScreen(userData: widget.userData),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: paginas,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF426A6C),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_rounded),
            label: 'Reportes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.restaurant_menu_outlined),
            label: 'Almuerzos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.campaign_outlined),
            label: 'Avisos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_alt_outlined),
            label: 'Empleados',
          ),
        ],
      ),
    );
  }
}
