import 'package:flutter/material.dart';
import '../services/admin_catalog_service.dart';
import 'admin_collection_page.dart';

/// Admin home: shows available catalogs to manage
class AdminHomePage extends StatelessWidget {
  const AdminHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final collections = AdminCatalogService.getCollectionList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin — Gestione Catalogo'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: collections.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final col = collections[index];
          return Card(
            elevation: 2,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              leading: CircleAvatar(
                backgroundColor: Colors.deepPurple.shade100,
                child: Icon(
                  _iconFor(col['icon']!),
                  color: Colors.deepPurple,
                ),
              ),
              title: Text(
                col['name']!,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              subtitle: Text('Catalogo: ${col['key']}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminCollectionPage(
                      collectionKey: col['key']!,
                      collectionName: col['name']!,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  IconData _iconFor(String iconName) {
    switch (iconName) {
      case 'catching_pokemon':
        return Icons.catching_pokemon;
      case 'auto_awesome':
        return Icons.auto_awesome;
      case 'sailing':
        return Icons.sailing;
      default:
        return Icons.style;
    }
  }
}
