import 'package:flutter/material.dart';
import 'reportes_admin_web.dart';
import 'dashboard_admin_web.dart';
import 'estadisticas_admin_web.dart'; // <--- 1. IMPORTA TU NUEVO ARCHIVO

class AdminLayout extends StatefulWidget {
  const AdminLayout({super.key});

  @override
  State<AdminLayout> createState() => _AdminLayoutState();
}

class _AdminLayoutState extends State<AdminLayout> {
  int _selectedIndex = 0; 
  static const Color primaryColor = Color(0xFF467879); 
  static const Color sidebarColor = Color(0xFF2C3E50); 

  // 2. ACTUALIZA LA LISTA DE DASHBOARDS
  final List<Widget> _dashboards = [
    const DashboardAdminWeb(),    // Índice 0: Panel General
    const EstadisticasAdminWeb(), // Índice 1: Análisis Estadístico (NUEVO)
    const ReportesAdminWeb(),     // Índice 2: Tabla de Reportes
    const Center(child: Text("👥 GESTIÓN DE PERSONAL DOCENTE", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // --- SIDEBAR PERSONALIZADO ---
          Container(
            width: 260,
            color: sidebarColor,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1A252F), 
                    border: Border(bottom: BorderSide(color: Colors.white10)),
                  ),
                  child: Column(
                    children: [
                      Image.asset(
                        'assets/images/logo_intesud1.png', 
                        height: 70,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => 
                          const Icon(Icons.account_balance, color: Colors.white, size: 50),
                      ),
                      const SizedBox(height: 15),
                      const Text(
                        "INTESUD", 
                        style: TextStyle(
                          color: Colors.white, 
                          fontWeight: FontWeight.bold, 
                          fontSize: 20,
                          letterSpacing: 1.5
                        ),
                      ),
                      const Text(
                        "Gestión de Reportes", 
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // OPCIONES DEL MENÚ (Asegúrate que el índice coincida con la lista _dashboards)
                _menuItem(0, Icons.dashboard_customize_outlined, "Dashboard"),
                _menuItem(1, Icons.analytics_outlined, "Estadísticas"),
                _menuItem(2, Icons.file_copy_outlined, "Reportes de Asistencia"),
                _menuItem(3, Icons.group_outlined, "Gestión Personal"),
                
                const Spacer(),
                
                const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text("v1.0.2 - 2026", style: TextStyle(color: Colors.white24, fontSize: 10)),
                )
              ],
            ),
          ),

          // --- ÁREA DE CONTENIDO ---
          Expanded(
            child: Column(
              children: [
                // NAVBAR SUPERIOR
                Container(
                  height: 65,
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(0, 2))],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.menu_open, color: primaryColor, size: 28),
                      const SizedBox(width: 20),
                      Text(
                        _getSectionTitle(), 
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87)
                      ),
                      const Spacer(),
                      // Perfil de Usuario
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: primaryColor,
                              child: Icon(Icons.person, size: 18, color: Colors.white),
                            ),
                            SizedBox(width: 8),
                            Text("Administrador RRHH", style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 15),
                      IconButton(
                        onPressed: () => Navigator.pushReplacementNamed(context, '/login'), 
                        icon: const Icon(Icons.power_settings_new, color: Colors.redAccent)
                      ),
                    ],
                  ),
                ),
                
                // CONTENIDO DINÁMICO
                Expanded(
                  child: Container(
                    color: const Color(0xFFF4F6F9), 
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _dashboards[_selectedIndex],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getSectionTitle() {
    switch (_selectedIndex) {
      case 0: return "Panel de Control General";
      case 1: return "Análisis Estadístico"; // Título para la nueva sección
      case 2: return "Reportes de Asistencia Mensual";
      case 3: return "Administración de Personal";
      default: return "Sistema INTESUD";
    }
  }

  Widget _menuItem(int index, IconData icon, String title) {
    bool isSelected = _selectedIndex == index;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: isSelected ? primaryColor : Colors.transparent,
      ),
      child: ListTile(
        onTap: () => setState(() => _selectedIndex = index),
        leading: Icon(
          icon, 
          color: isSelected ? Colors.white : Colors.white60,
          size: 22,
        ),
        title: Text(
          title, 
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          )
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}