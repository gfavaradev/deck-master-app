// ADMIN INTEGRATION EXAMPLE
// Questo file mostra come integrare la nuova AdminCatalogDesktopPage nell'app

import 'package:flutter/material.dart';
import 'package:deck_master/pages/admin_catalog_desktop_page.dart';
import 'package:deck_master/services/auth_service.dart';
import 'package:deck_master/utils/platform_helper.dart';

// ============================================================================
// ESEMPIO 1: Aggiungi al menu Settings per Admin
// ============================================================================

class SettingsPageWithAdminCatalog extends StatelessWidget {
  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: FutureBuilder<bool>(
        future: _authService.isCurrentUserAdmin(),
        builder: (context, snapshot) {
          final isAdmin = snapshot.data ?? false;

          return ListView(
            children: [
              // ... altre impostazioni ...

              // Sezione Admin (solo se utente è admin)
              if (isAdmin) ...[
                const Divider(),
                const ListTile(
                  title: Text(
                    'AMMINISTRAZIONE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),

                // Admin Catalog Desktop (solo per desktop/web)
                if (PlatformHelper.isDesktop || PlatformHelper.isWeb)
                  ListTile(
                    leading: const Icon(Icons.table_chart, color: Colors.deepPurple),
                    title: const Text('Gestione Catalogo Desktop'),
                    subtitle: const Text('Vista database completa per Windows/Web'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AdminCatalogDesktopPage(),
                        ),
                      );
                    },
                  ),

                // Admin Catalog Mobile (per mobile)
                if (PlatformHelper.isMobile)
                  ListTile(
                    leading: const Icon(Icons.admin_panel_settings, color: Colors.orange),
                    title: const Text('Gestione Catalogo'),
                    subtitle: const Text('Vista mobile ottimizzata'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Usa la vecchia pagina admin per mobile
                      // Navigator.push(...AdminCatalogPage()...)
                    },
                  ),

                // Altri strumenti admin
                ListTile(
                  leading: const Icon(Icons.people, color: Colors.blue),
                  title: const Text('Gestione Utenti'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // Navigate to user management
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// ESEMPIO 2: Route Protetta per Admin
// ============================================================================

class ProtectedAdminCatalogRoute extends StatelessWidget {
  const ProtectedAdminCatalogRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AuthService().isCurrentUserAdmin(),
      builder: (context, snapshot) {
        // Loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Not admin
        if (snapshot.data != true) {
          return Scaffold(
            appBar: AppBar(title: const Text('Accesso Negato')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'Accesso Riservato agli Amministratori',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('Non hai i permessi per accedere a questa sezione.'),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Torna Indietro'),
                  ),
                ],
              ),
            ),
          );
        }

        // Admin - show page
        return const AdminCatalogDesktopPage();
      },
    );
  }
}

// ============================================================================
// ESEMPIO 3: Admin Dashboard con Quick Access
// ============================================================================

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard Admin'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: GridView.count(
          crossAxisCount: PlatformHelper.isMobile ? 2 : 4,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: [
            _buildAdminCard(
              context,
              icon: Icons.table_chart,
              title: 'Catalogo Desktop',
              subtitle: 'Gestione database',
              color: Colors.deepPurple,
              onTap: () {
                if (PlatformHelper.isDesktop || PlatformHelper.isWeb) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AdminCatalogDesktopPage(),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Funzione disponibile solo su Desktop/Web'),
                    ),
                  );
                }
              },
            ),
            _buildAdminCard(
              context,
              icon: Icons.people,
              title: 'Utenti',
              subtitle: 'Gestione utenti',
              color: Colors.blue,
              onTap: () {
                // Navigate to users
              },
            ),
            _buildAdminCard(
              context,
              icon: Icons.analytics,
              title: 'Statistiche',
              subtitle: 'Analytics',
              color: Colors.green,
              onTap: () {
                // Navigate to stats
              },
            ),
            _buildAdminCard(
              context,
              icon: Icons.settings,
              title: 'Configurazione',
              subtitle: 'Impostazioni app',
              color: Colors.orange,
              onTap: () {
                // Navigate to config
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ESEMPIO 4: Named Routes (se usi named routing)
// ============================================================================

class AppRoutes {
  static const String home = '/';
  static const String settings = '/settings';
  static const String adminDashboard = '/admin';
  static const String adminCatalogDesktop = '/admin/catalog/desktop';
  static const String adminUsers = '/admin/users';

  static Map<String, WidgetBuilder> routes = {
    home: (context) => const HomePage(),
    settings: (context) => SettingsPageWithAdminCatalog(),
    adminDashboard: (context) => const ProtectedRoute(
          child: AdminDashboardPage(),
        ),
    adminCatalogDesktop: (context) => const ProtectedRoute(
          child: AdminCatalogDesktopPage(),
        ),
  };
}

class ProtectedRoute extends StatelessWidget {
  final Widget child;

  const ProtectedRoute({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AuthService().isCurrentUserAdmin(),
      builder: (context, snapshot) {
        if (snapshot.data == true) return child;
        return const Scaffold(
          body: Center(child: Text('Accesso negato')),
        );
      },
    );
  }
}

// Placeholder per HomePage
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: const Center(child: Text('Home Page')),
    );
  }
}

// ============================================================================
// ESEMPIO 5: FloatingActionButton per Quick Access (in home page admin)
// ============================================================================

class HomePageWithAdminFAB extends StatelessWidget {
  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _authService.isCurrentUserAdmin(),
      builder: (context, snapshot) {
        final isAdmin = snapshot.data ?? false;

        return Scaffold(
          appBar: AppBar(title: const Text('Deck Master')),
          body: const Center(child: Text('Home')),
          // FAB Admin solo se è desktop e utente è admin
          floatingActionButton: isAdmin &&
                  (PlatformHelper.isDesktop || PlatformHelper.isWeb)
              ? FloatingActionButton.extended(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AdminCatalogDesktopPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.admin_panel_settings),
                  label: const Text('Admin Catalog'),
                  backgroundColor: Colors.deepPurple,
                )
              : null,
        );
      },
    );
  }
}

// ============================================================================
// ESEMPIO 6: Side Drawer con Admin Section
// ============================================================================

class AppDrawerWithAdmin extends StatelessWidget {
  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: FutureBuilder<bool>(
        future: _authService.isCurrentUserAdmin(),
        builder: (context, snapshot) {
          final isAdmin = snapshot.data ?? false;

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              const DrawerHeader(
                decoration: BoxDecoration(color: Colors.deepPurple),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Deck Master',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Admin Panel',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),

              // User items
              ListTile(
                leading: const Icon(Icons.home),
                title: const Text('Home'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.style),
                title: const Text('Le Mie Carte'),
                onTap: () {/* navigate */},
              ),

              // Admin section
              if (isAdmin) ...[
                const Divider(),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'AMMINISTRAZIONE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                if (PlatformHelper.isDesktop || PlatformHelper.isWeb)
                  ListTile(
                    leading: const Icon(Icons.table_chart, color: Colors.deepPurple),
                    title: const Text('Catalogo Desktop'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AdminCatalogDesktopPage(),
                        ),
                      );
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.people, color: Colors.blue),
                  title: const Text('Gestione Utenti'),
                  onTap: () {/* navigate */},
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// NOTE IMPORTANTI
// ============================================================================

/*
1. PLATFORM CHECK
   - Usa sempre PlatformHelper per verificare la piattaforma
   - Desktop/Web: mostra AdminCatalogDesktopPage
   - Mobile: usa la vecchia AdminCatalogPage o un'alternativa mobile

2. ADMIN CHECK
   - Verifica sempre isCurrentUserAdmin() prima di mostrare opzioni admin
   - Usa FutureBuilder per gestire il caricamento asincrono

3. NAVIGATION
   - Usa Navigator.push per navigation diretta
   - Oppure usa named routes per app più grandi

4. UX
   - Mostra feedback chiaro se funzione non disponibile su piattaforma
   - Usa icone e colori consistenti per funzioni admin
   - Badge o indicatori per modifiche pendenti

5. PERFORMANCE
   - La pagina desktop è ottimizzata per schermi grandi
   - Non è adatta per mobile (layout diverso necessario)
   - Usa lazy loading dove possibile
*/
