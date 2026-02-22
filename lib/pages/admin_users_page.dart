import 'package:flutter/material.dart';
import 'package:deck_master/models/user_model.dart';
import 'package:deck_master/services/user_service.dart';

/// Admin page for managing users and their roles
class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  final UserService _userService = UserService();
  List<UserModel> _users = [];
  bool _isLoading = true;
  String _filterRole = 'all'; // 'all', 'administrator', 'user'

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);

    try {
      final users = _filterRole == 'all'
          ? await _userService.getAllUsers()
          : await _userService.getUsersByRole(
              _filterRole == 'administrator'
                  ? UserRole.administrator
                  : UserRole.user
            );

      if (mounted) {
        setState(() {
          _users = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore caricamento utenti: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestione Utenti'),
        backgroundColor: Colors.orange,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUsers,
            tooltip: 'Ricarica',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterChips(),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _users.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('Nessun utente trovato', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : _buildUsersList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Text('Filtro: ', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Tutti'),
            selected: _filterRole == 'all',
            onSelected: (selected) {
              if (selected) {
                setState(() => _filterRole = 'all');
                _loadUsers();
              }
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Admin'),
            selected: _filterRole == 'administrator',
            selectedColor: Colors.orange.shade200,
            onSelected: (selected) {
              if (selected) {
                setState(() => _filterRole = 'administrator');
                _loadUsers();
              }
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Utenti'),
            selected: _filterRole == 'user',
            onSelected: (selected) {
              if (selected) {
                setState(() => _filterRole = 'user');
                _loadUsers();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildUsersList() {
    return ListView.builder(
      itemCount: _users.length,
      itemBuilder: (context, index) {
        final user = _users[index];
        return _buildUserCard(user);
      },
    );
  }

  Widget _buildUserCard(UserModel user) {
    final isCurrentUser = user.uid == _userService.currentUserId;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage: user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
          backgroundColor: user.isAdmin ? Colors.orange : Colors.blue,
          child: user.photoUrl == null
              ? Icon(
                  user.isAdmin ? Icons.admin_panel_settings : Icons.person,
                  color: Colors.white,
                )
              : null,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                user.displayName ?? 'Utente senza nome',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (isCurrentUser)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Tu',
                  style: TextStyle(fontSize: 10, color: Colors.blue),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.email),
            const SizedBox(height: 4),
            Row(
              children: [
                _buildRoleBadge(user.role),
                const SizedBox(width: 8),
                if (!user.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'DISATTIVATO',
                      style: TextStyle(fontSize: 10, color: Colors.red),
                    ),
                  ),
              ],
            ),
            if (user.lastLoginAt != null)
              Text(
                'Ultimo accesso: ${_formatDate(user.lastLoginAt!)}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
          ],
        ),
        trailing: !isCurrentUser
            ? PopupMenuButton<String>(
                onSelected: (value) => _handleUserAction(value, user),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'toggle_role',
                    child: Row(
                      children: [
                        Icon(
                          user.isAdmin ? Icons.person : Icons.admin_panel_settings,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          user.isAdmin ? 'Rendi Utente' : 'Rendi Admin',
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle_active',
                    child: Row(
                      children: [
                        Icon(
                          user.isActive ? Icons.block : Icons.check_circle,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          user.isActive ? 'Disattiva' : 'Attiva',
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 20, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Elimina', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _buildRoleBadge(UserRole role) {
    final isAdmin = role == UserRole.administrator;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isAdmin ? Colors.orange.shade100 : Colors.blue.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isAdmin ? 'ADMIN' : 'USER',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isAdmin ? Colors.orange.shade900 : Colors.blue.shade900,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        return '${diff.inMinutes}m fa';
      }
      return '${diff.inHours}h fa';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}g fa';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Future<void> _handleUserAction(String action, UserModel user) async {
    switch (action) {
      case 'toggle_role':
        await _toggleUserRole(user);
        break;
      case 'toggle_active':
        await _toggleActiveStatus(user);
        break;
      case 'delete':
        await _deleteUser(user);
        break;
    }
  }

  Future<void> _toggleUserRole(UserModel user) async {
    final newRole = user.isAdmin ? UserRole.user : UserRole.administrator;
    final roleText = newRole == UserRole.administrator ? 'amministratore' : 'utente';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conferma cambio ruolo'),
        content: Text(
          'Vuoi cambiare il ruolo di ${user.displayName ?? user.email} a $roleText?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Conferma'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _userService.updateUserRole(user.uid, newRole);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ruolo aggiornato con successo')),
          );
          _loadUsers();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Errore: $e')),
          );
        }
      }
    }
  }

  Future<void> _toggleActiveStatus(UserModel user) async {
    final newStatus = !user.isActive;
    final statusText = newStatus ? 'attivare' : 'disattivare';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Conferma ${statusText}zione'),
        content: Text(
          'Vuoi $statusText l\'account di ${user.displayName ?? user.email}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: newStatus ? Colors.green : Colors.red,
            ),
            child: const Text('Conferma'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _userService.setUserActiveStatus(user.uid, newStatus);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Stato aggiornato: ${newStatus ? "Attivo" : "Disattivato"}')),
          );
          _loadUsers();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Errore: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteUser(UserModel user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conferma eliminazione'),
        content: Text(
          'Sei sicuro di voler eliminare l\'utente ${user.displayName ?? user.email}?\n\n'
          'ATTENZIONE: Questa azione è irreversibile!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _userService.deleteUser(user.uid);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Utente eliminato con successo')),
          );
          _loadUsers();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Errore: $e')),
          );
        }
      }
    }
  }
}
