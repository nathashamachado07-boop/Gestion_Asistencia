import 'package:flutter/material.dart';
import 'reportes_rrhh_screen.dart';
import 'almuerzos_rrhh_screen.dart';
import 'avisos_rrhh_screen.dart';
import 'empleados_rrhh_screen.dart';

class NavRRHHScreen extends StatefulWidget {
  @override
  _NavRRHHScreenState createState() => _NavRRHHScreenState();
}

class _NavRRHHScreenState extends State<NavRRHHScreen> {
  int _currentIndex = 0;

  // Lista de las páginas que creaste
  final List<Widget> _paginas = [
    ReportesRRHHScreen(),
    AlmuerzosRRHHScreen(),
    AvisosRRHHScreen(),
    EmpleadosRRHHScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _paginas[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Color(0xFF426A6C), // Tu verde petróleo
        unselectedItemColor: Colors.grey,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Reportes'),
          BottomNavigationBarItem(icon: Icon(Icons.restaurant), label: 'Almuerzos'),
          BottomNavigationBarItem(icon: Icon(Icons.campaign), label: 'Avisos'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Empleados'),
        ],
      ),
    );
  }
}