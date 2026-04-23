import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tipo di sblocco dell'avatar.
enum AvatarUnlockType { level, collection }

/// Definisce un avatar sbloccabile.
class AvatarDef {
  final String id;
  final String name;
  final AvatarUnlockType unlockType;
  // Level-based
  final int? unlockLevel;
  // Collection-based
  final String? collectionKey;
  final int? unlockPercent; // 10-100

  final IconData icon;
  final Color background;
  final Color iconColor;

  const AvatarDef({
    required this.id,
    required this.name,
    required this.unlockType,
    this.unlockLevel,
    this.collectionKey,
    this.unlockPercent,
    required this.icon,
    required this.background,
    required this.iconColor,
  });

  bool isUnlocked(int accountLevel, Map<String, double> completions) {
    if (unlockType == AvatarUnlockType.level) {
      return accountLevel >= (unlockLevel ?? 1);
    }
    final c = completions[collectionKey] ?? 0.0;
    return (c * 100) >= (unlockPercent ?? 100);
  }

  Widget buildCircle(double radius) => CircleAvatar(
        radius: radius,
        backgroundColor: background,
        child: Icon(icon, size: radius * 0.9, color: iconColor),
      );
}

/// Metadata per ogni collezione nel sistema avatar.
class CollectionAvatarMeta {
  final String key;
  final String name;

  const CollectionAvatarMeta(this.key, this.name);
}

/// Gestisce il sistema XP/livelli e gli avatar sbloccabili.
class XpService {
  static final XpService _instance = XpService._internal();
  factory XpService() => _instance;
  XpService._internal();

  static const String _xpKey = 'user_xp';
  static const String _avatarKey = 'selected_avatar_id';

  /// Soglie XP per ogni livello (indice 0 = livello 1), curva quadratica.
  /// Livello 100 = ~750.000 XP (completamento di tutte le 20 collezioni).
  static const List<int> levelThresholds = [
    0,       77,      306,     689,     1224,    1913,    2755,    3750,    4897,    6198,    // 1-10
    7652,    9259,    11019,   12932,   14998,   17218,   19590,   22115,   24793,   27625,   // 11-20
    30609,   33746,   37037,   40480,   44077,   47826,   51729,   55785,   59993,   64355,   // 21-30
    68870,   73538,   78358,   83332,   88459,   93739,   99172,   104758,  110497,  116389,  // 31-40
    122435,  128633,  134984,  141488,  148146,  154956,  161919,  169036,  176305,  183728,  // 41-50
    191303,  199032,  206913,  214948,  223136,  231477,  239970,  248617,  257417,  266370,  // 51-60
    275476,  284735,  294147,  303712,  313430,  323301,  333325,  343503,  353833,  364316,  // 61-70
    374953,  385742,  396684,  407780,  419028,  430430,  441984,  453692,  465553,  477566,  // 71-80
    489733,  502053,  514526,  527152,  539930,  552862,  565947,  579185,  592576,  606121,  // 81-90
    619818,  633668,  647671,  661827,  676137,  690599,  705214,  719983,  734904,  750000,  // 91-100
  ];

  /// Collezioni disponibili nel sistema avatar (ordinate).
  static const List<CollectionAvatarMeta> collections = [
    CollectionAvatarMeta('yugioh',            'Yu-Gi-Oh!'),
    CollectionAvatarMeta('pokemon',           'Pokémon'),
    CollectionAvatarMeta('onepiece',          'One Piece TCG'),
    CollectionAvatarMeta('magic',             'Magic: The Gathering'),
    CollectionAvatarMeta('lorcana',           'Lorcana'),
    CollectionAvatarMeta('riftbound',         'Riftbound'),
    CollectionAvatarMeta('flesh_blood',       'Flesh and Blood'),
    CollectionAvatarMeta('starwars_unlimited','Star Wars Unlimited'),
    CollectionAvatarMeta('digimon',           'Digimon'),
    CollectionAvatarMeta('dragonball',        'Dragon Ball SCG'),
    CollectionAvatarMeta('vanguard',          'Cardfight!! Vanguard'),
    CollectionAvatarMeta('weiss_schwarz',     'Weiß Schwarz'),
    CollectionAvatarMeta('final_fantasy',     'Final Fantasy TCG'),
    CollectionAvatarMeta('force_of_will',     'Force of Will'),
    CollectionAvatarMeta('battle_spirits',    'Battle Spirits Saga'),
    CollectionAvatarMeta('wow',               'World of Warcraft TCG'),
    CollectionAvatarMeta('starwars_destiny',  'Star Wars Destiny'),
    CollectionAvatarMeta('dragoborne',        'Dragoborne'),
    CollectionAvatarMeta('little_pony',       'My Little Pony CCG'),
    CollectionAvatarMeta('the_spoils',        'The Spoils'),
  ];

  /// Tutti gli avatar disponibili.
  /// 10 globali (livello account) + 20 per ognuna delle 20 collezioni (completamento %).
  /// Totale: 410 avatar.
  static const List<AvatarDef> avatars = [
    // ── Globali ──────────────────────────────────────────────────────────────
    AvatarDef(id: 'global_1',  name: 'Collezionista',  unlockType: AvatarUnlockType.level, unlockLevel: 10,
      icon: Icons.style,             background: Color(0xFF455A64), iconColor: Color(0xFFB0BEC5)),
    AvatarDef(id: 'global_2',  name: 'Esperto',        unlockType: AvatarUnlockType.level, unlockLevel: 20,
      icon: Icons.workspace_premium, background: Color(0xFF1565C0), iconColor: Color(0xFF90CAF9)),
    AvatarDef(id: 'global_3',  name: 'Veterano',       unlockType: AvatarUnlockType.level, unlockLevel: 30,
      icon: Icons.military_tech,     background: Color(0xFF2E7D32), iconColor: Color(0xFFA5D6A7)),
    AvatarDef(id: 'global_4',  name: 'Maestro',        unlockType: AvatarUnlockType.level, unlockLevel: 40,
      icon: Icons.emoji_events,      background: Color(0xFFE65100), iconColor: Color(0xFFFFCC80)),
    AvatarDef(id: 'global_5',  name: 'Campione',       unlockType: AvatarUnlockType.level, unlockLevel: 50,
      icon: Icons.stars,             background: Color(0xFF6A1B9A), iconColor: Color(0xFFCE93D8)),
    AvatarDef(id: 'global_6',  name: 'Elite',          unlockType: AvatarUnlockType.level, unlockLevel: 60,
      icon: Icons.diamond,           background: Color(0xFF1565C0), iconColor: Color(0xFFBBDEFB)),
    AvatarDef(id: 'global_7',  name: 'Gran Maestro',   unlockType: AvatarUnlockType.level, unlockLevel: 70,
      icon: Icons.auto_awesome,      background: Color(0xFF880E4F), iconColor: Color(0xFFF48FB1)),
    AvatarDef(id: 'global_8',  name: 'Leggenda',       unlockType: AvatarUnlockType.level, unlockLevel: 80,
      icon: Icons.brightness_7,      background: Color(0xFF212121), iconColor: Color(0xFFFDD835)),
    AvatarDef(id: 'global_9',  name: 'Mito',           unlockType: AvatarUnlockType.level, unlockLevel: 90,
      icon: Icons.public,            background: Color(0xFF0D0D0D), iconColor: Color(0xFFFFAB40)),
    AvatarDef(id: 'global_10', name: 'Dio del Gioco',  unlockType: AvatarUnlockType.level, unlockLevel: 100,
      icon: Icons.flare,             background: Color(0xFF000000), iconColor: Color(0xFFFDD835)),

    // ── Yu-Gi-Oh! ────────────────────────────────────────────────────────────
    AvatarDef(id: 'ygo_1',  name: 'Curioso del Duello',    unlockType: AvatarUnlockType.collection, collectionKey: 'yugioh', unlockPercent: 5,
      icon: Icons.person_pin,          background: Color(0xFF5C2580), iconColor: Color(0xFFCE93D8)),
    AvatarDef(id: 'ygo_2',  name: 'Apprendista Duellante', unlockType: AvatarUnlockType.collection, collectionKey: 'yugioh', unlockPercent: 10,
      icon: Icons.person_pin,          background: Color(0xFF5C2580), iconColor: Color(0xFFCE93D8)),
    AvatarDef(id: 'ygo_3',  name: 'Duellante Junior',      unlockType: AvatarUnlockType.collection, collectionKey: 'yugioh', unlockPercent: 15,
      icon: Icons.sports_martial_arts, background: Color(0xFF6A1B9A), iconColor: Color(0xFFE1BEE7)),
    AvatarDef(id: 'ygo_4',  name: 'Duellante',             unlockType: AvatarUnlockType.collection, collectionKey: 'yugioh', unlockPercent: 20,
      icon: Icons.sports_martial_arts, background: Color(0xFF6A1B9A), iconColor: Color(0xFFE1BEE7)),
    AvatarDef(id: 'ygo_5',  name: 'Duellante Emergente',   unlockType: AvatarUnlockType.collection, collectionKey: 'yugioh', unlockPercent: 25,
      icon: Icons.badge,               background: Color(0xFF7B1FA2), iconColor: Color(0xFFE1BEE7)),
    AvatarDef(id: 'ygo_6',  name: 'Duellante Veterano',    unlockType: AvatarUnlockType.collection, collectionKey: 'yugioh', unlockPercent: 30,
      icon: Icons.badge,               background: Color(0xFF7B1FA2), iconColor: Color(0xFFE1BEE7)),
    AvatarDef(id: 'ygo_7',  name: 'Duellante Esperto',     unlockType: AvatarUnlockType.collection, collectionKey: 'yugioh', unlockPercent: 35,
      icon: Icons.military_tech,       background: Color(0xFF6200EA), iconColor: Color(0xFFB39DDB)),
    AvatarDef(id: 'ygo_8',  name: "Duellante d'Elite",     unlockType: AvatarUnlockType.collection, collectionKey: 'yugioh', unlockPercent: 40,
      icon: Icons.military_tech,       background: Color(0xFF6200EA), iconColor: Color(0xFFB39DDB)),
    AvatarDef(id: 'ygo_9',  name: 'Semi-Finalista',        unlockType: AvatarUnlockType.collection, collectionKey: 'yugioh', unlockPercent: 45,
      icon: Icons.emoji_events,        background: Color(0xFF4A148C), iconColor: Color(0xFFCE93D8)),
    AvatarDef(id: 'ygo_10', name: 'Campione Regionale',    unlockType: AvatarUnlockType.collection, collectionKey: 'yugioh', unlockPercent: 50,
      icon: Icons.emoji_events,        background: Color(0xFF4A148C), iconColor: Color(0xFFCE93D8)),
    AvatarDef(id: 'ygo_11', name: 'Campione di Circuito',  unlockType: AvatarUnlockType.collection, collectionKey: 'yugioh', unlockPercent: 55,
      icon: Icons.diamond,             background: Color(0xFF311B92), iconColor: Color(0xFFD1C4E9)),
    AvatarDef(id: 'ygo_12', name: 'Elite Duellante',       unlockType: AvatarUnlockType.collection, collectionKey: 'yugioh', unlockPercent: 60,
      icon: Icons.diamond,             background: Color(0xFF311B92), iconColor: Color(0xFFD1C4E9)),
    AvatarDef(id: 'ygo_13', name: 'Duellante Pro',         unlockType: AvatarUnlockType.collection, collectionKey: 'yugioh', unlockPercent: 65,
      icon: Icons.workspace_premium,   background: Color(0xFF1A0061), iconColor: Color(0xFFB39DDB)),
    AvatarDef(id: 'ygo_14', name: 'Pro Duellante',         unlockType: AvatarUnlockType.collection, collectionKey: 'yugioh', unlockPercent: 70,
      icon: Icons.workspace_premium,   background: Color(0xFF1A0061), iconColor: Color(0xFFB39DDB)),
    AvatarDef(id: 'ygo_15', name: 'Maestro Duellante',     unlockType: AvatarUnlockType.collection, collectionKey: 'yugioh', unlockPercent: 75,
      icon: Icons.auto_awesome,        background: Color(0xFF10003B), iconColor: Color(0xFFB39DDB)),
    AvatarDef(id: 'ygo_16', name: 'Maestro del Mazzo',     unlockType: AvatarUnlockType.collection, collectionKey: 'yugioh', unlockPercent: 80,
      icon: Icons.auto_awesome,        background: Color(0xFF10003B), iconColor: Color(0xFFB39DDB)),
    AvatarDef(id: 'ygo_17', name: 'Gran Duellante',        unlockType: AvatarUnlockType.collection, collectionKey: 'yugioh', unlockPercent: 85,
      icon: Icons.stars,               background: Color(0xFF0A0020), iconColor: Color(0xFFCE93D8)),
    AvatarDef(id: 'ygo_18', name: 'Leggenda del Duello',   unlockType: AvatarUnlockType.collection, collectionKey: 'yugioh', unlockPercent: 90,
      icon: Icons.stars,               background: Color(0xFF0A0020), iconColor: Color(0xFFCE93D8)),
    AvatarDef(id: 'ygo_19', name: 'Quasi Leggendario',     unlockType: AvatarUnlockType.collection, collectionKey: 'yugioh', unlockPercent: 95,
      icon: Icons.flare,               background: Color(0xFF1A0033), iconColor: Color(0xFFFDD835)),
    AvatarDef(id: 'ygo_20', name: 'Re dei Giochi',         unlockType: AvatarUnlockType.collection, collectionKey: 'yugioh', unlockPercent: 100,
      icon: Icons.flare,               background: Color(0xFF1A0033), iconColor: Color(0xFFFDD835)),

    // ── Pokémon ──────────────────────────────────────────────────────────────
    AvatarDef(id: 'pkm_1',  name: 'Curioso di Pokémon',  unlockType: AvatarUnlockType.collection, collectionKey: 'pokemon', unlockPercent: 5,
      icon: Icons.sports,            background: Color(0xFFC62828), iconColor: Color(0xFFEF9A9A)),
    AvatarDef(id: 'pkm_2',  name: 'Allenatore Novizio',  unlockType: AvatarUnlockType.collection, collectionKey: 'pokemon', unlockPercent: 10,
      icon: Icons.sports,            background: Color(0xFFC62828), iconColor: Color(0xFFEF9A9A)),
    AvatarDef(id: 'pkm_3',  name: 'Allenatore Junior',   unlockType: AvatarUnlockType.collection, collectionKey: 'pokemon', unlockPercent: 15,
      icon: Icons.badge,             background: Color(0xFFB71C1C), iconColor: Color(0xFFFFCDD2)),
    AvatarDef(id: 'pkm_4',  name: 'Allenatore',          unlockType: AvatarUnlockType.collection, collectionKey: 'pokemon', unlockPercent: 20,
      icon: Icons.badge,             background: Color(0xFFB71C1C), iconColor: Color(0xFFFFCDD2)),
    AvatarDef(id: 'pkm_5',  name: 'Allenatore Emergente',unlockType: AvatarUnlockType.collection, collectionKey: 'pokemon', unlockPercent: 25,
      icon: Icons.military_tech,     background: Color(0xFFB71C1C), iconColor: Color(0xFFFFCDD2)),
    AvatarDef(id: 'pkm_6',  name: 'Allenatore Esperto',  unlockType: AvatarUnlockType.collection, collectionKey: 'pokemon', unlockPercent: 30,
      icon: Icons.military_tech,     background: Color(0xFFB71C1C), iconColor: Color(0xFFFFCDD2)),
    AvatarDef(id: 'pkm_7',  name: 'Allenatore Avanzato', unlockType: AvatarUnlockType.collection, collectionKey: 'pokemon', unlockPercent: 35,
      icon: Icons.workspace_premium, background: Color(0xFFA31515), iconColor: Color(0xFFFF8A80)),
    AvatarDef(id: 'pkm_8',  name: 'Supervisore di Lega', unlockType: AvatarUnlockType.collection, collectionKey: 'pokemon', unlockPercent: 40,
      icon: Icons.workspace_premium, background: Color(0xFFA31515), iconColor: Color(0xFFFF8A80)),
    AvatarDef(id: 'pkm_9',  name: 'Assistente Capopalestra', unlockType: AvatarUnlockType.collection, collectionKey: 'pokemon', unlockPercent: 45,
      icon: Icons.emoji_events,      background: Color(0xFF8B0000), iconColor: Color(0xFFFFCDD2)),
    AvatarDef(id: 'pkm_10', name: 'Capopalestra',        unlockType: AvatarUnlockType.collection, collectionKey: 'pokemon', unlockPercent: 50,
      icon: Icons.emoji_events,      background: Color(0xFF8B0000), iconColor: Color(0xFFFFCDD2)),
    AvatarDef(id: 'pkm_11', name: 'Arbitro di Lega',     unlockType: AvatarUnlockType.collection, collectionKey: 'pokemon', unlockPercent: 55,
      icon: Icons.diamond,           background: Color(0xFF7F0000), iconColor: Color(0xFFFF8A80)),
    AvatarDef(id: 'pkm_12', name: 'Elite 4',             unlockType: AvatarUnlockType.collection, collectionKey: 'pokemon', unlockPercent: 60,
      icon: Icons.diamond,           background: Color(0xFF7F0000), iconColor: Color(0xFFFF8A80)),
    AvatarDef(id: 'pkm_13', name: 'Accademico Senior',   unlockType: AvatarUnlockType.collection, collectionKey: 'pokemon', unlockPercent: 65,
      icon: Icons.auto_awesome,      background: Color(0xFF6D0000), iconColor: Color(0xFFFF6E40)),
    AvatarDef(id: 'pkm_14', name: 'Accademico Pokémon',  unlockType: AvatarUnlockType.collection, collectionKey: 'pokemon', unlockPercent: 70,
      icon: Icons.auto_awesome,      background: Color(0xFF6D0000), iconColor: Color(0xFFFF6E40)),
    AvatarDef(id: 'pkm_15', name: 'Consulente Elite',    unlockType: AvatarUnlockType.collection, collectionKey: 'pokemon', unlockPercent: 75,
      icon: Icons.stars,             background: Color(0xFF560000), iconColor: Color(0xFFFF5252)),
    AvatarDef(id: 'pkm_16', name: "Membro dell'Alto Consiglio", unlockType: AvatarUnlockType.collection, collectionKey: 'pokemon', unlockPercent: 80,
      icon: Icons.stars,             background: Color(0xFF560000), iconColor: Color(0xFFFF5252)),
    AvatarDef(id: 'pkm_17', name: 'Rivale del Campione', unlockType: AvatarUnlockType.collection, collectionKey: 'pokemon', unlockPercent: 85,
      icon: Icons.brightness_7,      background: Color(0xFF3E0000), iconColor: Color(0xFFFF4040)),
    AvatarDef(id: 'pkm_18', name: 'Vice Campione',       unlockType: AvatarUnlockType.collection, collectionKey: 'pokemon', unlockPercent: 90,
      icon: Icons.brightness_7,      background: Color(0xFF3E0000), iconColor: Color(0xFFFF4040)),
    AvatarDef(id: 'pkm_19', name: 'Sfidante al Titolo',  unlockType: AvatarUnlockType.collection, collectionKey: 'pokemon', unlockPercent: 95,
      icon: Icons.flare,             background: Color(0xFF3E0000), iconColor: Color(0xFFFDD835)),
    AvatarDef(id: 'pkm_20', name: 'Campione Pokémon',    unlockType: AvatarUnlockType.collection, collectionKey: 'pokemon', unlockPercent: 100,
      icon: Icons.flare,             background: Color(0xFF3E0000), iconColor: Color(0xFFFDD835)),

    // ── One Piece TCG ─────────────────────────────────────────────────────────
    AvatarDef(id: 'op_1',  name: 'Curioso del Mare',    unlockType: AvatarUnlockType.collection, collectionKey: 'onepiece', unlockPercent: 5,
      icon: Icons.sailing,       background: Color(0xFFE65100), iconColor: Color(0xFFFFCC80)),
    AvatarDef(id: 'op_2',  name: 'Marinaio',            unlockType: AvatarUnlockType.collection, collectionKey: 'onepiece', unlockPercent: 10,
      icon: Icons.sailing,       background: Color(0xFFE65100), iconColor: Color(0xFFFFCC80)),
    AvatarDef(id: 'op_3',  name: 'Pirata Novizio',      unlockType: AvatarUnlockType.collection, collectionKey: 'onepiece', unlockPercent: 15,
      icon: Icons.explore,       background: Color(0xFFD44D00), iconColor: Color(0xFFFFAB91)),
    AvatarDef(id: 'op_4',  name: 'Pirata',              unlockType: AvatarUnlockType.collection, collectionKey: 'onepiece', unlockPercent: 20,
      icon: Icons.explore,       background: Color(0xFFD44D00), iconColor: Color(0xFFFFAB91)),
    AvatarDef(id: 'op_5',  name: 'Pirata Emergente',    unlockType: AvatarUnlockType.collection, collectionKey: 'onepiece', unlockPercent: 25,
      icon: Icons.flag,          background: Color(0xFFBF360C), iconColor: Color(0xFFFFAB91)),
    AvatarDef(id: 'op_6',  name: 'Sottocapo',           unlockType: AvatarUnlockType.collection, collectionKey: 'onepiece', unlockPercent: 30,
      icon: Icons.flag,          background: Color(0xFFBF360C), iconColor: Color(0xFFFFAB91)),
    AvatarDef(id: 'op_7',  name: 'Capitano Rivale',     unlockType: AvatarUnlockType.collection, collectionKey: 'onepiece', unlockPercent: 35,
      icon: Icons.security,      background: Color(0xFFA63400), iconColor: Color(0xFFFF8A65)),
    AvatarDef(id: 'op_8',  name: 'Capitano',            unlockType: AvatarUnlockType.collection, collectionKey: 'onepiece', unlockPercent: 40,
      icon: Icons.security,      background: Color(0xFFA63400), iconColor: Color(0xFFFF8A65)),
    AvatarDef(id: 'op_9',  name: 'Corsaro Emergente',   unlockType: AvatarUnlockType.collection, collectionKey: 'onepiece', unlockPercent: 45,
      icon: Icons.military_tech, background: Color(0xFF870000), iconColor: Color(0xFFFF7043)),
    AvatarDef(id: 'op_10', name: 'Corsaro',             unlockType: AvatarUnlockType.collection, collectionKey: 'onepiece', unlockPercent: 50,
      icon: Icons.military_tech, background: Color(0xFF870000), iconColor: Color(0xFFFF7043)),
    AvatarDef(id: 'op_11', name: 'Warlord Emergente',   unlockType: AvatarUnlockType.collection, collectionKey: 'onepiece', unlockPercent: 55,
      icon: Icons.workspace_premium, background: Color(0xFF6D1000), iconColor: Color(0xFFFF6E40)),
    AvatarDef(id: 'op_12', name: 'Signore della Guerra',unlockType: AvatarUnlockType.collection, collectionKey: 'onepiece', unlockPercent: 60,
      icon: Icons.workspace_premium, background: Color(0xFF6D1000), iconColor: Color(0xFFFF6E40)),
    AvatarDef(id: 'op_13', name: 'Imperatore Nascente', unlockType: AvatarUnlockType.collection, collectionKey: 'onepiece', unlockPercent: 65,
      icon: Icons.diamond,       background: Color(0xFF560000), iconColor: Color(0xFFFF6E40)),
    AvatarDef(id: 'op_14', name: 'Imperatore dei Mari', unlockType: AvatarUnlockType.collection, collectionKey: 'onepiece', unlockPercent: 70,
      icon: Icons.diamond,       background: Color(0xFF560000), iconColor: Color(0xFFFF6E40)),
    AvatarDef(id: 'op_15', name: 'Ammiraglio Anziano',  unlockType: AvatarUnlockType.collection, collectionKey: 'onepiece', unlockPercent: 75,
      icon: Icons.stars,         background: Color(0xFF3E0000), iconColor: Color(0xFFFF8A65)),
    AvatarDef(id: 'op_16', name: 'Ammiraglio',          unlockType: AvatarUnlockType.collection, collectionKey: 'onepiece', unlockPercent: 80,
      icon: Icons.stars,         background: Color(0xFF3E0000), iconColor: Color(0xFFFF8A65)),
    AvatarDef(id: 'op_17', name: 'Leggenda Nascente',   unlockType: AvatarUnlockType.collection, collectionKey: 'onepiece', unlockPercent: 85,
      icon: Icons.auto_awesome,  background: Color(0xFF250000), iconColor: Color(0xFFFFAB91)),
    AvatarDef(id: 'op_18', name: 'Leggenda del Mare',   unlockType: AvatarUnlockType.collection, collectionKey: 'onepiece', unlockPercent: 90,
      icon: Icons.auto_awesome,  background: Color(0xFF250000), iconColor: Color(0xFFFFAB91)),
    AvatarDef(id: 'op_19', name: 'Erede del Re',        unlockType: AvatarUnlockType.collection, collectionKey: 'onepiece', unlockPercent: 95,
      icon: Icons.flare,         background: Color(0xFF1A0000), iconColor: Color(0xFFFDD835)),
    AvatarDef(id: 'op_20', name: 'Re dei Pirati',       unlockType: AvatarUnlockType.collection, collectionKey: 'onepiece', unlockPercent: 100,
      icon: Icons.flare,         background: Color(0xFF1A0000), iconColor: Color(0xFFFDD835)),

    // ── Magic: The Gathering ──────────────────────────────────────────────────
    AvatarDef(id: 'mtg_1',  name: 'Curioso della Magia', unlockType: AvatarUnlockType.collection, collectionKey: 'magic', unlockPercent: 5,
      icon: Icons.psychology,        background: Color(0xFF0D47A1), iconColor: Color(0xFF90CAF9)),
    AvatarDef(id: 'mtg_2',  name: 'Studente di Magia',   unlockType: AvatarUnlockType.collection, collectionKey: 'magic', unlockPercent: 10,
      icon: Icons.psychology,        background: Color(0xFF0D47A1), iconColor: Color(0xFF90CAF9)),
    AvatarDef(id: 'mtg_3',  name: 'Apprendista Avanzato',unlockType: AvatarUnlockType.collection, collectionKey: 'magic', unlockPercent: 15,
      icon: Icons.auto_fix_high,     background: Color(0xFF1565C0), iconColor: Color(0xFFBBDEFB)),
    AvatarDef(id: 'mtg_4',  name: 'Apprendista Mago',    unlockType: AvatarUnlockType.collection, collectionKey: 'magic', unlockPercent: 20,
      icon: Icons.auto_fix_high,     background: Color(0xFF1565C0), iconColor: Color(0xFFBBDEFB)),
    AvatarDef(id: 'mtg_5',  name: 'Mago Emergente',      unlockType: AvatarUnlockType.collection, collectionKey: 'magic', unlockPercent: 25,
      icon: Icons.electric_bolt,     background: Color(0xFF01579B), iconColor: Color(0xFFB3E5FC)),
    AvatarDef(id: 'mtg_6',  name: 'Mago',                unlockType: AvatarUnlockType.collection, collectionKey: 'magic', unlockPercent: 30,
      icon: Icons.electric_bolt,     background: Color(0xFF01579B), iconColor: Color(0xFFB3E5FC)),
    AvatarDef(id: 'mtg_7',  name: 'Evocatore Esperto',   unlockType: AvatarUnlockType.collection, collectionKey: 'magic', unlockPercent: 35,
      icon: Icons.stars,             background: Color(0xFF0A3880), iconColor: Color(0xFF82B1FF)),
    AvatarDef(id: 'mtg_8',  name: 'Evocatore',           unlockType: AvatarUnlockType.collection, collectionKey: 'magic', unlockPercent: 40,
      icon: Icons.stars,             background: Color(0xFF0A3880), iconColor: Color(0xFF82B1FF)),
    AvatarDef(id: 'mtg_9',  name: 'Stregone Emergente',  unlockType: AvatarUnlockType.collection, collectionKey: 'magic', unlockPercent: 45,
      icon: Icons.military_tech,     background: Color(0xFF002171), iconColor: Color(0xFF64B5F6)),
    AvatarDef(id: 'mtg_10', name: 'Stregone',            unlockType: AvatarUnlockType.collection, collectionKey: 'magic', unlockPercent: 50,
      icon: Icons.military_tech,     background: Color(0xFF002171), iconColor: Color(0xFF64B5F6)),
    AvatarDef(id: 'mtg_11', name: 'Arcimago Junior',     unlockType: AvatarUnlockType.collection, collectionKey: 'magic', unlockPercent: 55,
      icon: Icons.workspace_premium, background: Color(0xFF001A5E), iconColor: Color(0xFF90CAF9)),
    AvatarDef(id: 'mtg_12', name: 'Arcimago',            unlockType: AvatarUnlockType.collection, collectionKey: 'magic', unlockPercent: 60,
      icon: Icons.workspace_premium, background: Color(0xFF001A5E), iconColor: Color(0xFF90CAF9)),
    AvatarDef(id: 'mtg_13', name: 'Planeswalker Emergente', unlockType: AvatarUnlockType.collection, collectionKey: 'magic', unlockPercent: 65,
      icon: Icons.public,            background: Color(0xFF001040), iconColor: Color(0xFF64B5F6)),
    AvatarDef(id: 'mtg_14', name: 'Planeswalker',        unlockType: AvatarUnlockType.collection, collectionKey: 'magic', unlockPercent: 70,
      icon: Icons.public,            background: Color(0xFF001040), iconColor: Color(0xFF64B5F6)),
    AvatarDef(id: 'mtg_15', name: 'Senatore Junior',     unlockType: AvatarUnlockType.collection, collectionKey: 'magic', unlockPercent: 75,
      icon: Icons.diamond,           background: Color(0xFF000D33), iconColor: Color(0xFF90CAF9)),
    AvatarDef(id: 'mtg_16', name: 'Senatore del Consiglio', unlockType: AvatarUnlockType.collection, collectionKey: 'magic', unlockPercent: 80,
      icon: Icons.diamond,           background: Color(0xFF000D33), iconColor: Color(0xFF90CAF9)),
    AvatarDef(id: 'mtg_17', name: 'Campione Nascente',   unlockType: AvatarUnlockType.collection, collectionKey: 'magic', unlockPercent: 85,
      icon: Icons.auto_awesome,      background: Color(0xFF000823), iconColor: Color(0xFFBBDEFB)),
    AvatarDef(id: 'mtg_18', name: 'Campione dei Piani',  unlockType: AvatarUnlockType.collection, collectionKey: 'magic', unlockPercent: 90,
      icon: Icons.auto_awesome,      background: Color(0xFF000823), iconColor: Color(0xFFBBDEFB)),
    AvatarDef(id: 'mtg_19', name: 'Signore Nascente',    unlockType: AvatarUnlockType.collection, collectionKey: 'magic', unlockPercent: 95,
      icon: Icons.brightness_7,      background: Color(0xFF000051), iconColor: Color(0xFFFDD835)),
    AvatarDef(id: 'mtg_20', name: 'Signore dei Piani',   unlockType: AvatarUnlockType.collection, collectionKey: 'magic', unlockPercent: 100,
      icon: Icons.brightness_7,      background: Color(0xFF000051), iconColor: Color(0xFFFDD835)),

    // ── Lorcana ───────────────────────────────────────────────────────────────
    AvatarDef(id: 'lcn_1',  name: 'Curioso dei Sogni',   unlockType: AvatarUnlockType.collection, collectionKey: 'lorcana', unlockPercent: 5,
      icon: Icons.bedtime,           background: Color(0xFF4527A0), iconColor: Color(0xFFD1C4E9)),
    AvatarDef(id: 'lcn_2',  name: 'Sognatore',           unlockType: AvatarUnlockType.collection, collectionKey: 'lorcana', unlockPercent: 10,
      icon: Icons.bedtime,           background: Color(0xFF4527A0), iconColor: Color(0xFFD1C4E9)),
    AvatarDef(id: 'lcn_3',  name: 'Cercatore Avanzato',  unlockType: AvatarUnlockType.collection, collectionKey: 'lorcana', unlockPercent: 15,
      icon: Icons.search,            background: Color(0xFF3D1F95), iconColor: Color(0xFFC5CAE9)),
    AvatarDef(id: 'lcn_4',  name: 'Cercatore di Storie', unlockType: AvatarUnlockType.collection, collectionKey: 'lorcana', unlockPercent: 20,
      icon: Icons.search,            background: Color(0xFF3D1F95), iconColor: Color(0xFFC5CAE9)),
    AvatarDef(id: 'lcn_5',  name: 'Illumineer Junior',   unlockType: AvatarUnlockType.collection, collectionKey: 'lorcana', unlockPercent: 25,
      icon: Icons.lightbulb,         background: Color(0xFF311B92), iconColor: Color(0xFFEDE7F6)),
    AvatarDef(id: 'lcn_6',  name: 'Illumineer',          unlockType: AvatarUnlockType.collection, collectionKey: 'lorcana', unlockPercent: 30,
      icon: Icons.lightbulb,         background: Color(0xFF311B92), iconColor: Color(0xFFEDE7F6)),
    AvatarDef(id: 'lcn_7',  name: 'Tessitore Esperto',   unlockType: AvatarUnlockType.collection, collectionKey: 'lorcana', unlockPercent: 35,
      icon: Icons.book,              background: Color(0xFF280E80), iconColor: Color(0xFFD1C4E9)),
    AvatarDef(id: 'lcn_8',  name: 'Tessitore di Sogni',  unlockType: AvatarUnlockType.collection, collectionKey: 'lorcana', unlockPercent: 40,
      icon: Icons.book,              background: Color(0xFF280E80), iconColor: Color(0xFFD1C4E9)),
    AvatarDef(id: 'lcn_9',  name: 'Guardiano Junior',    unlockType: AvatarUnlockType.collection, collectionKey: 'lorcana', unlockPercent: 45,
      icon: Icons.menu_book,         background: Color(0xFF1A237E), iconColor: Color(0xFFC5CAE9)),
    AvatarDef(id: 'lcn_10', name: 'Guardiano del Lore',  unlockType: AvatarUnlockType.collection, collectionKey: 'lorcana', unlockPercent: 50,
      icon: Icons.menu_book,         background: Color(0xFF1A237E), iconColor: Color(0xFFC5CAE9)),
    AvatarDef(id: 'lcn_11', name: 'Custode Esperto',     unlockType: AvatarUnlockType.collection, collectionKey: 'lorcana', unlockPercent: 55,
      icon: Icons.military_tech,     background: Color(0xFF13196B), iconColor: Color(0xFFB39DDB)),
    AvatarDef(id: 'lcn_12', name: 'Custode Anziano',     unlockType: AvatarUnlockType.collection, collectionKey: 'lorcana', unlockPercent: 60,
      icon: Icons.military_tech,     background: Color(0xFF13196B), iconColor: Color(0xFFB39DDB)),
    AvatarDef(id: 'lcn_13', name: 'Maestro Junior',      unlockType: AvatarUnlockType.collection, collectionKey: 'lorcana', unlockPercent: 65,
      icon: Icons.stars,             background: Color(0xFF0D1060), iconColor: Color(0xFFD1C4E9)),
    AvatarDef(id: 'lcn_14', name: 'Maestro Illumineer',  unlockType: AvatarUnlockType.collection, collectionKey: 'lorcana', unlockPercent: 70,
      icon: Icons.stars,             background: Color(0xFF0D1060), iconColor: Color(0xFFD1C4E9)),
    AvatarDef(id: 'lcn_15', name: 'Oracolo Junior',      unlockType: AvatarUnlockType.collection, collectionKey: 'lorcana', unlockPercent: 75,
      icon: Icons.workspace_premium, background: Color(0xFF070A40), iconColor: Color(0xFFC5CAE9)),
    AvatarDef(id: 'lcn_16', name: 'Oracolo dei Sogni',   unlockType: AvatarUnlockType.collection, collectionKey: 'lorcana', unlockPercent: 80,
      icon: Icons.workspace_premium, background: Color(0xFF070A40), iconColor: Color(0xFFC5CAE9)),
    AvatarDef(id: 'lcn_17', name: 'Araldo Junior',       unlockType: AvatarUnlockType.collection, collectionKey: 'lorcana', unlockPercent: 85,
      icon: Icons.diamond,           background: Color(0xFF040620), iconColor: Color(0xFFB39DDB)),
    AvatarDef(id: 'lcn_18', name: 'Araldo del Destino',  unlockType: AvatarUnlockType.collection, collectionKey: 'lorcana', unlockPercent: 90,
      icon: Icons.diamond,           background: Color(0xFF040620), iconColor: Color(0xFFB39DDB)),
    AvatarDef(id: 'lcn_19', name: 'Gran Custode',        unlockType: AvatarUnlockType.collection, collectionKey: 'lorcana', unlockPercent: 95,
      icon: Icons.auto_awesome,      background: Color(0xFF0D0D3B), iconColor: Color(0xFFFDD835)),
    AvatarDef(id: 'lcn_20', name: 'Gran Illumineer',     unlockType: AvatarUnlockType.collection, collectionKey: 'lorcana', unlockPercent: 100,
      icon: Icons.auto_awesome,      background: Color(0xFF0D0D3B), iconColor: Color(0xFFFDD835)),

    // ── Riftbound ─────────────────────────────────────────────────────────────
    AvatarDef(id: 'rift_1',  name: 'Curioso del Rift',         unlockType: AvatarUnlockType.collection, collectionKey: 'riftbound', unlockPercent: 5,
      icon: Icons.explore,           background: Color(0xFF004D40), iconColor: Color(0xFF80CBC4)),
    AvatarDef(id: 'rift_2',  name: 'Esploratore',              unlockType: AvatarUnlockType.collection, collectionKey: 'riftbound', unlockPercent: 10,
      icon: Icons.explore,           background: Color(0xFF004D40), iconColor: Color(0xFF80CBC4)),
    AvatarDef(id: 'rift_3',  name: 'Scout Avanzato',           unlockType: AvatarUnlockType.collection, collectionKey: 'riftbound', unlockPercent: 15,
      icon: Icons.search,            background: Color(0xFF00443A), iconColor: Color(0xFF4DB6AC)),
    AvatarDef(id: 'rift_4',  name: 'Scout del Rift',           unlockType: AvatarUnlockType.collection, collectionKey: 'riftbound', unlockPercent: 20,
      icon: Icons.search,            background: Color(0xFF00443A), iconColor: Color(0xFF4DB6AC)),
    AvatarDef(id: 'rift_5',  name: 'Ricercatore Esperto',      unlockType: AvatarUnlockType.collection, collectionKey: 'riftbound', unlockPercent: 25,
      icon: Icons.radar,             background: Color(0xFF003B32), iconColor: Color(0xFF26A69A)),
    AvatarDef(id: 'rift_6',  name: 'Ricercatore',              unlockType: AvatarUnlockType.collection, collectionKey: 'riftbound', unlockPercent: 30,
      icon: Icons.radar,             background: Color(0xFF003B32), iconColor: Color(0xFF26A69A)),
    AvatarDef(id: 'rift_7',  name: 'Investigatore Senior',     unlockType: AvatarUnlockType.collection, collectionKey: 'riftbound', unlockPercent: 35,
      icon: Icons.navigation,        background: Color(0xFF00332A), iconColor: Color(0xFF1DE9B6)),
    AvatarDef(id: 'rift_8',  name: 'Investigatore',            unlockType: AvatarUnlockType.collection, collectionKey: 'riftbound', unlockPercent: 40,
      icon: Icons.navigation,        background: Color(0xFF00332A), iconColor: Color(0xFF1DE9B6)),
    AvatarDef(id: 'rift_9',  name: 'Cacciatore Esperto',       unlockType: AvatarUnlockType.collection, collectionKey: 'riftbound', unlockPercent: 45,
      icon: Icons.gps_fixed,         background: Color(0xFF002822), iconColor: Color(0xFF00BFA5)),
    AvatarDef(id: 'rift_10', name: 'Cacciatore del Rift',      unlockType: AvatarUnlockType.collection, collectionKey: 'riftbound', unlockPercent: 50,
      icon: Icons.gps_fixed,         background: Color(0xFF002822), iconColor: Color(0xFF00BFA5)),
    AvatarDef(id: 'rift_11', name: 'Navigatore Esperto',       unlockType: AvatarUnlockType.collection, collectionKey: 'riftbound', unlockPercent: 55,
      icon: Icons.open_with,         background: Color(0xFF002018), iconColor: Color(0xFF00897B)),
    AvatarDef(id: 'rift_12', name: 'Navigatore delle Fenditure', unlockType: AvatarUnlockType.collection, collectionKey: 'riftbound', unlockPercent: 60,
      icon: Icons.open_with,         background: Color(0xFF002018), iconColor: Color(0xFF00897B)),
    AvatarDef(id: 'rift_13', name: 'Apripista Esperto',        unlockType: AvatarUnlockType.collection, collectionKey: 'riftbound', unlockPercent: 65,
      icon: Icons.stars,             background: Color(0xFF001810), iconColor: Color(0xFF80CBC4)),
    AvatarDef(id: 'rift_14', name: 'Apripista',                unlockType: AvatarUnlockType.collection, collectionKey: 'riftbound', unlockPercent: 70,
      icon: Icons.stars,             background: Color(0xFF001810), iconColor: Color(0xFF80CBC4)),
    AvatarDef(id: 'rift_15', name: 'Guardiano Senior',         unlockType: AvatarUnlockType.collection, collectionKey: 'riftbound', unlockPercent: 75,
      icon: Icons.security,          background: Color(0xFF001008), iconColor: Color(0xFF4DB6AC)),
    AvatarDef(id: 'rift_16', name: 'Guardiano del Confine',    unlockType: AvatarUnlockType.collection, collectionKey: 'riftbound', unlockPercent: 80,
      icon: Icons.security,          background: Color(0xFF001008), iconColor: Color(0xFF4DB6AC)),
    AvatarDef(id: 'rift_17', name: 'Sentinella Senior',        unlockType: AvatarUnlockType.collection, collectionKey: 'riftbound', unlockPercent: 85,
      icon: Icons.workspace_premium, background: Color(0xFF000C06), iconColor: Color(0xFF80CBC4)),
    AvatarDef(id: 'rift_18', name: 'Sentinella del Rift',      unlockType: AvatarUnlockType.collection, collectionKey: 'riftbound', unlockPercent: 90,
      icon: Icons.workspace_premium, background: Color(0xFF000C06), iconColor: Color(0xFF80CBC4)),
    AvatarDef(id: 'rift_19', name: 'Riftwalker Avanzato',      unlockType: AvatarUnlockType.collection, collectionKey: 'riftbound', unlockPercent: 95,
      icon: Icons.blur_circular,     background: Color(0xFF001B12), iconColor: Color(0xFFFDD835)),
    AvatarDef(id: 'rift_20', name: 'Riftwalker Supremo',       unlockType: AvatarUnlockType.collection, collectionKey: 'riftbound', unlockPercent: 100,
      icon: Icons.blur_circular,     background: Color(0xFF001B12), iconColor: Color(0xFFFDD835)),

    // ── Flesh and Blood ───────────────────────────────────────────────────────
    AvatarDef(id: 'fab_1',  name: 'Curioso del Combattimento', unlockType: AvatarUnlockType.collection, collectionKey: 'flesh_blood', unlockPercent: 5,
      icon: Icons.directions_run,    background: Color(0xFF4E342E), iconColor: Color(0xFFBCAAA4)),
    AvatarDef(id: 'fab_2',  name: 'Avventuriero',          unlockType: AvatarUnlockType.collection, collectionKey: 'flesh_blood', unlockPercent: 10,
      icon: Icons.directions_run,    background: Color(0xFF4E342E), iconColor: Color(0xFFBCAAA4)),
    AvatarDef(id: 'fab_3',  name: 'Guerriero Junior',      unlockType: AvatarUnlockType.collection, collectionKey: 'flesh_blood', unlockPercent: 15,
      icon: Icons.fitness_center,    background: Color(0xFF462C28), iconColor: Color(0xFFD7CCC8)),
    AvatarDef(id: 'fab_4',  name: 'Guerriero',             unlockType: AvatarUnlockType.collection, collectionKey: 'flesh_blood', unlockPercent: 20,
      icon: Icons.fitness_center,    background: Color(0xFF462C28), iconColor: Color(0xFFD7CCC8)),
    AvatarDef(id: 'fab_5',  name: 'Lottatore Esperto',     unlockType: AvatarUnlockType.collection, collectionKey: 'flesh_blood', unlockPercent: 25,
      icon: Icons.sports_martial_arts, background: Color(0xFF3E2723), iconColor: Color(0xFFD7CCC8)),
    AvatarDef(id: 'fab_6',  name: 'Lottatore',             unlockType: AvatarUnlockType.collection, collectionKey: 'flesh_blood', unlockPercent: 30,
      icon: Icons.sports_martial_arts, background: Color(0xFF3E2723), iconColor: Color(0xFFD7CCC8)),
    AvatarDef(id: 'fab_7',  name: 'Campione Emergente',    unlockType: AvatarUnlockType.collection, collectionKey: 'flesh_blood', unlockPercent: 35,
      icon: Icons.shield,            background: Color(0xFF6D1212), iconColor: Color(0xFFFF8A80)),
    AvatarDef(id: 'fab_8',  name: 'Campione',              unlockType: AvatarUnlockType.collection, collectionKey: 'flesh_blood', unlockPercent: 40,
      icon: Icons.shield,            background: Color(0xFF6D1212), iconColor: Color(0xFFFF8A80)),
    AvatarDef(id: 'fab_9',  name: 'Eroe Emergente',        unlockType: AvatarUnlockType.collection, collectionKey: 'flesh_blood', unlockPercent: 45,
      icon: Icons.security,          background: Color(0xFF5A0F0F), iconColor: Color(0xFFFFAB91)),
    AvatarDef(id: 'fab_10', name: 'Eroe',                  unlockType: AvatarUnlockType.collection, collectionKey: 'flesh_blood', unlockPercent: 50,
      icon: Icons.security,          background: Color(0xFF5A0F0F), iconColor: Color(0xFFFFAB91)),
    AvatarDef(id: 'fab_11', name: 'Leggenda Emergente',    unlockType: AvatarUnlockType.collection, collectionKey: 'flesh_blood', unlockPercent: 55,
      icon: Icons.military_tech,     background: Color(0xFF690000), iconColor: Color(0xFFFF8A80)),
    AvatarDef(id: 'fab_12', name: 'Leggenda della Battaglia', unlockType: AvatarUnlockType.collection, collectionKey: 'flesh_blood', unlockPercent: 60,
      icon: Icons.military_tech,     background: Color(0xFF690000), iconColor: Color(0xFFFF8A80)),
    AvatarDef(id: 'fab_13', name: 'Guardiano Junior',      unlockType: AvatarUnlockType.collection, collectionKey: 'flesh_blood', unlockPercent: 65,
      icon: Icons.workspace_premium, background: Color(0xFF520000), iconColor: Color(0xFFFF6E40)),
    AvatarDef(id: 'fab_14', name: 'Guardiano Eterno',      unlockType: AvatarUnlockType.collection, collectionKey: 'flesh_blood', unlockPercent: 70,
      icon: Icons.workspace_premium, background: Color(0xFF520000), iconColor: Color(0xFFFF6E40)),
    AvatarDef(id: 'fab_15', name: 'Paladino Junior',       unlockType: AvatarUnlockType.collection, collectionKey: 'flesh_blood', unlockPercent: 75,
      icon: Icons.diamond,           background: Color(0xFF3B0000), iconColor: Color(0xFFFF5252)),
    AvatarDef(id: 'fab_16', name: 'Paladino Immortale',    unlockType: AvatarUnlockType.collection, collectionKey: 'flesh_blood', unlockPercent: 80,
      icon: Icons.diamond,           background: Color(0xFF3B0000), iconColor: Color(0xFFFF5252)),
    AvatarDef(id: 'fab_17', name: 'Campione Senior',       unlockType: AvatarUnlockType.collection, collectionKey: 'flesh_blood', unlockPercent: 85,
      icon: Icons.stars,             background: Color(0xFF2A0000), iconColor: Color(0xFFFF8A80)),
    AvatarDef(id: 'fab_18', name: 'Campione Leggendario',  unlockType: AvatarUnlockType.collection, collectionKey: 'flesh_blood', unlockPercent: 90,
      icon: Icons.stars,             background: Color(0xFF2A0000), iconColor: Color(0xFFFF8A80)),
    AvatarDef(id: 'fab_19', name: 'Eroe Nascente',         unlockType: AvatarUnlockType.collection, collectionKey: 'flesh_blood', unlockPercent: 95,
      icon: Icons.emoji_events,      background: Color(0xFF3B0000), iconColor: Color(0xFFFDD835)),
    AvatarDef(id: 'fab_20', name: 'Eroe Immortale',        unlockType: AvatarUnlockType.collection, collectionKey: 'flesh_blood', unlockPercent: 100,
      icon: Icons.emoji_events,      background: Color(0xFF3B0000), iconColor: Color(0xFFFDD835)),

    // ── Star Wars Unlimited ───────────────────────────────────────────────────
    AvatarDef(id: 'swu_1',  name: 'Curioso della Galassia', unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_unlimited', unlockPercent: 5,
      icon: Icons.person,            background: Color(0xFF263238), iconColor: Color(0xFF78909C)),
    AvatarDef(id: 'swu_2',  name: 'Civile',                 unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_unlimited', unlockPercent: 10,
      icon: Icons.person,            background: Color(0xFF263238), iconColor: Color(0xFF78909C)),
    AvatarDef(id: 'swu_3',  name: 'Ribelle Avanzato',       unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_unlimited', unlockPercent: 15,
      icon: Icons.radio_button_checked, background: Color(0xFF212121), iconColor: Color(0xFF9E9E9E)),
    AvatarDef(id: 'swu_4',  name: 'Ribelle',                unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_unlimited', unlockPercent: 20,
      icon: Icons.radio_button_checked, background: Color(0xFF212121), iconColor: Color(0xFF9E9E9E)),
    AvatarDef(id: 'swu_5',  name: 'Soldato Esperto',        unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_unlimited', unlockPercent: 25,
      icon: Icons.security,          background: Color(0xFF1E1E1E), iconColor: Color(0xFFBDBDBD)),
    AvatarDef(id: 'swu_6',  name: 'Soldato',                unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_unlimited', unlockPercent: 30,
      icon: Icons.security,          background: Color(0xFF1E1E1E), iconColor: Color(0xFFBDBDBD)),
    AvatarDef(id: 'swu_7',  name: 'Pilota Esperto',         unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_unlimited', unlockPercent: 35,
      icon: Icons.send,              background: Color(0xFF1A1A1A), iconColor: Color(0xFFEEEEEE)),
    AvatarDef(id: 'swu_8',  name: 'Pilota',                 unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_unlimited', unlockPercent: 40,
      icon: Icons.send,              background: Color(0xFF1A1A1A), iconColor: Color(0xFFEEEEEE)),
    AvatarDef(id: 'swu_9',  name: 'Cavaliere Avanzato',     unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_unlimited', unlockPercent: 45,
      icon: Icons.star_border,       background: Color(0xFF151515), iconColor: Color(0xFFE0E0E0)),
    AvatarDef(id: 'swu_10', name: 'Cavaliere',              unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_unlimited', unlockPercent: 50,
      icon: Icons.star_border,       background: Color(0xFF151515), iconColor: Color(0xFFE0E0E0)),
    AvatarDef(id: 'swu_11', name: 'Comandante Junior',      unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_unlimited', unlockPercent: 55,
      icon: Icons.military_tech,     background: Color(0xFF111111), iconColor: Color(0xFFE0E0E0)),
    AvatarDef(id: 'swu_12', name: 'Comandante',             unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_unlimited', unlockPercent: 60,
      icon: Icons.military_tech,     background: Color(0xFF111111), iconColor: Color(0xFFE0E0E0)),
    AvatarDef(id: 'swu_13', name: 'Generale Junior',        unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_unlimited', unlockPercent: 65,
      icon: Icons.stars,             background: Color(0xFF0D0D0D), iconColor: Color(0xFFBDBDBD)),
    AvatarDef(id: 'swu_14', name: 'Generale',               unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_unlimited', unlockPercent: 70,
      icon: Icons.stars,             background: Color(0xFF0D0D0D), iconColor: Color(0xFFBDBDBD)),
    AvatarDef(id: 'swu_15', name: 'Gran Maestro Junior',    unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_unlimited', unlockPercent: 75,
      icon: Icons.workspace_premium, background: Color(0xFF0A0A0A), iconColor: Color(0xFF9E9E9E)),
    AvatarDef(id: 'swu_16', name: 'Gran Maestro Jedi',      unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_unlimited', unlockPercent: 80,
      icon: Icons.workspace_premium, background: Color(0xFF0A0A0A), iconColor: Color(0xFF9E9E9E)),
    AvatarDef(id: 'swu_17', name: 'Campione Nascente',      unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_unlimited', unlockPercent: 85,
      icon: Icons.diamond,           background: Color(0xFF050505), iconColor: Color(0xFFE0E0E0)),
    AvatarDef(id: 'swu_18', name: 'Campione della Galassia',unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_unlimited', unlockPercent: 90,
      icon: Icons.diamond,           background: Color(0xFF050505), iconColor: Color(0xFFE0E0E0)),
    AvatarDef(id: 'swu_19', name: 'Guardiano Nascente',     unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_unlimited', unlockPercent: 95,
      icon: Icons.auto_awesome,      background: Color(0xFF0A0A0A), iconColor: Color(0xFFFDD835)),
    AvatarDef(id: 'swu_20', name: 'Guardiano della Pace',   unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_unlimited', unlockPercent: 100,
      icon: Icons.auto_awesome,      background: Color(0xFF0A0A0A), iconColor: Color(0xFFFDD835)),

    // ── Digimon ───────────────────────────────────────────────────────────────
    AvatarDef(id: 'digi_1',  name: 'Curioso del Digitale',   unlockType: AvatarUnlockType.collection, collectionKey: 'digimon', unlockPercent: 5,
      icon: Icons.wifi,              background: Color(0xFF1565C0), iconColor: Color(0xFF90CAF9)),
    AvatarDef(id: 'digi_2',  name: 'DigiDestinat',           unlockType: AvatarUnlockType.collection, collectionKey: 'digimon', unlockPercent: 10,
      icon: Icons.wifi,              background: Color(0xFF1565C0), iconColor: Color(0xFF90CAF9)),
    AvatarDef(id: 'digi_3',  name: 'Tamer Junior',           unlockType: AvatarUnlockType.collection, collectionKey: 'digimon', unlockPercent: 15,
      icon: Icons.smartphone,        background: Color(0xFF1052A0), iconColor: Color(0xFFBBDEFB)),
    AvatarDef(id: 'digi_4',  name: 'Tamer Novizio',          unlockType: AvatarUnlockType.collection, collectionKey: 'digimon', unlockPercent: 20,
      icon: Icons.smartphone,        background: Color(0xFF1052A0), iconColor: Color(0xFFBBDEFB)),
    AvatarDef(id: 'digi_5',  name: 'Tamer Avanzato',         unlockType: AvatarUnlockType.collection, collectionKey: 'digimon', unlockPercent: 25,
      icon: Icons.pets,              background: Color(0xFF0D47A1), iconColor: Color(0xFFBBDEFB)),
    AvatarDef(id: 'digi_6',  name: 'Tamer',                  unlockType: AvatarUnlockType.collection, collectionKey: 'digimon', unlockPercent: 30,
      icon: Icons.pets,              background: Color(0xFF0D47A1), iconColor: Color(0xFFBBDEFB)),
    AvatarDef(id: 'digi_7',  name: 'Tamer Senior',           unlockType: AvatarUnlockType.collection, collectionKey: 'digimon', unlockPercent: 35,
      icon: Icons.badge,             background: Color(0xFF083880), iconColor: Color(0xFF82B1FF)),
    AvatarDef(id: 'digi_8',  name: 'Tamer Veterano',         unlockType: AvatarUnlockType.collection, collectionKey: 'digimon', unlockPercent: 40,
      icon: Icons.badge,             background: Color(0xFF083880), iconColor: Color(0xFF82B1FF)),
    AvatarDef(id: 'digi_9',  name: 'Champion Junior',        unlockType: AvatarUnlockType.collection, collectionKey: 'digimon', unlockPercent: 45,
      icon: Icons.workspace_premium, background: Color(0xFF052B6B), iconColor: Color(0xFF64B5F6)),
    AvatarDef(id: 'digi_10', name: 'Champion Tamer',         unlockType: AvatarUnlockType.collection, collectionKey: 'digimon', unlockPercent: 50,
      icon: Icons.workspace_premium, background: Color(0xFF052B6B), iconColor: Color(0xFF64B5F6)),
    AvatarDef(id: 'digi_11', name: 'Ultimate Junior',        unlockType: AvatarUnlockType.collection, collectionKey: 'digimon', unlockPercent: 55,
      icon: Icons.military_tech,     background: Color(0xFF031E50), iconColor: Color(0xFF90CAF9)),
    AvatarDef(id: 'digi_12', name: 'Ultimate Tamer',         unlockType: AvatarUnlockType.collection, collectionKey: 'digimon', unlockPercent: 60,
      icon: Icons.military_tech,     background: Color(0xFF031E50), iconColor: Color(0xFF90CAF9)),
    AvatarDef(id: 'digi_13', name: 'Mega Junior',            unlockType: AvatarUnlockType.collection, collectionKey: 'digimon', unlockPercent: 65,
      icon: Icons.stars,             background: Color(0xFF021540), iconColor: Color(0xFF64B5F6)),
    AvatarDef(id: 'digi_14', name: 'Mega Tamer',             unlockType: AvatarUnlockType.collection, collectionKey: 'digimon', unlockPercent: 70,
      icon: Icons.stars,             background: Color(0xFF021540), iconColor: Color(0xFF64B5F6)),
    AvatarDef(id: 'digi_15', name: 'Digimon Campione',       unlockType: AvatarUnlockType.collection, collectionKey: 'digimon', unlockPercent: 75,
      icon: Icons.diamond,           background: Color(0xFF010C28), iconColor: Color(0xFFBBDEFB)),
    AvatarDef(id: 'digi_16', name: 'Re dei Digimon',         unlockType: AvatarUnlockType.collection, collectionKey: 'digimon', unlockPercent: 80,
      icon: Icons.diamond,           background: Color(0xFF010C28), iconColor: Color(0xFFBBDEFB)),
    AvatarDef(id: 'digi_17', name: "Tamer d'Elite",          unlockType: AvatarUnlockType.collection, collectionKey: 'digimon', unlockPercent: 85,
      icon: Icons.auto_awesome,      background: Color(0xFF000820), iconColor: Color(0xFF82B1FF)),
    AvatarDef(id: 'digi_18', name: 'Tamer Supremo',          unlockType: AvatarUnlockType.collection, collectionKey: 'digimon', unlockPercent: 90,
      icon: Icons.auto_awesome,      background: Color(0xFF000820), iconColor: Color(0xFF82B1FF)),
    AvatarDef(id: 'digi_19', name: 'Imperatore Nascente',    unlockType: AvatarUnlockType.collection, collectionKey: 'digimon', unlockPercent: 95,
      icon: Icons.flash_on,          background: Color(0xFF000D40), iconColor: Color(0xFFFDD835)),
    AvatarDef(id: 'digi_20', name: 'Imperatore del Mondo Digitale', unlockType: AvatarUnlockType.collection, collectionKey: 'digimon', unlockPercent: 100,
      icon: Icons.flash_on,          background: Color(0xFF000D40), iconColor: Color(0xFFFDD835)),

    // ── Dragon Ball SCG ───────────────────────────────────────────────────────
    AvatarDef(id: 'db_1',  name: 'Curioso del Ki',          unlockType: AvatarUnlockType.collection, collectionKey: 'dragonball', unlockPercent: 5,
      icon: Icons.person,            background: Color(0xFFE65100), iconColor: Color(0xFFFFCC80)),
    AvatarDef(id: 'db_2',  name: 'Terrestre',               unlockType: AvatarUnlockType.collection, collectionKey: 'dragonball', unlockPercent: 10,
      icon: Icons.person,            background: Color(0xFFE65100), iconColor: Color(0xFFFFCC80)),
    AvatarDef(id: 'db_3',  name: 'Guerriero Z Junior',      unlockType: AvatarUnlockType.collection, collectionKey: 'dragonball', unlockPercent: 15,
      icon: Icons.fitness_center,    background: Color(0xFFD84500), iconColor: Color(0xFFFFAB91)),
    AvatarDef(id: 'db_4',  name: 'Guerriero Z',             unlockType: AvatarUnlockType.collection, collectionKey: 'dragonball', unlockPercent: 20,
      icon: Icons.fitness_center,    background: Color(0xFFD84500), iconColor: Color(0xFFFFAB91)),
    AvatarDef(id: 'db_5',  name: 'Super Saiyan Emergente',  unlockType: AvatarUnlockType.collection, collectionKey: 'dragonball', unlockPercent: 25,
      icon: Icons.bolt,              background: Color(0xFFBF360C), iconColor: Color(0xFFFFCC00)),
    AvatarDef(id: 'db_6',  name: 'Super Saiyan',            unlockType: AvatarUnlockType.collection, collectionKey: 'dragonball', unlockPercent: 30,
      icon: Icons.bolt,              background: Color(0xFFBF360C), iconColor: Color(0xFFFFCC00)),
    AvatarDef(id: 'db_7',  name: 'Super Saiyan 2 Junior',   unlockType: AvatarUnlockType.collection, collectionKey: 'dragonball', unlockPercent: 35,
      icon: Icons.flash_on,          background: Color(0xFFA32E0A), iconColor: Color(0xFFFFE082)),
    AvatarDef(id: 'db_8',  name: 'Super Saiyan 2',          unlockType: AvatarUnlockType.collection, collectionKey: 'dragonball', unlockPercent: 40,
      icon: Icons.flash_on,          background: Color(0xFFA32E0A), iconColor: Color(0xFFFFE082)),
    AvatarDef(id: 'db_9',  name: 'Super Saiyan 3 Junior',   unlockType: AvatarUnlockType.collection, collectionKey: 'dragonball', unlockPercent: 45,
      icon: Icons.electric_bolt,     background: Color(0xFF8A2508), iconColor: Color(0xFFFFD740)),
    AvatarDef(id: 'db_10', name: 'Super Saiyan 3',          unlockType: AvatarUnlockType.collection, collectionKey: 'dragonball', unlockPercent: 50,
      icon: Icons.electric_bolt,     background: Color(0xFF8A2508), iconColor: Color(0xFFFFD740)),
    AvatarDef(id: 'db_11', name: 'Super Saiyan God Junior', unlockType: AvatarUnlockType.collection, collectionKey: 'dragonball', unlockPercent: 55,
      icon: Icons.brightness_7,      background: Color(0xFF701500), iconColor: Color(0xFFFF6E40)),
    AvatarDef(id: 'db_12', name: 'Super Saiyan God',        unlockType: AvatarUnlockType.collection, collectionKey: 'dragonball', unlockPercent: 60,
      icon: Icons.brightness_7,      background: Color(0xFF701500), iconColor: Color(0xFFFF6E40)),
    AvatarDef(id: 'db_13', name: 'Super Saiyan Blue Junior',unlockType: AvatarUnlockType.collection, collectionKey: 'dragonball', unlockPercent: 65,
      icon: Icons.star,              background: Color(0xFF5A0F00), iconColor: Color(0xFFFF8A65)),
    AvatarDef(id: 'db_14', name: 'Super Saiyan Blue',       unlockType: AvatarUnlockType.collection, collectionKey: 'dragonball', unlockPercent: 70,
      icon: Icons.star,              background: Color(0xFF5A0F00), iconColor: Color(0xFFFF8A65)),
    AvatarDef(id: 'db_15', name: 'Ultra Instinct Junior',   unlockType: AvatarUnlockType.collection, collectionKey: 'dragonball', unlockPercent: 75,
      icon: Icons.auto_awesome,      background: Color(0xFF4A0E00), iconColor: Color(0xFFFFCC80)),
    AvatarDef(id: 'db_16', name: 'Ultra Instinct',          unlockType: AvatarUnlockType.collection, collectionKey: 'dragonball', unlockPercent: 80,
      icon: Icons.auto_awesome,      background: Color(0xFF4A0E00), iconColor: Color(0xFFFFCC80)),
    AvatarDef(id: 'db_17', name: 'Campione Nascente',       unlockType: AvatarUnlockType.collection, collectionKey: 'dragonball', unlockPercent: 85,
      icon: Icons.public,            background: Color(0xFF300900), iconColor: Color(0xFFFFAB91)),
    AvatarDef(id: 'db_18', name: 'Campione Universale',     unlockType: AvatarUnlockType.collection, collectionKey: 'dragonball', unlockPercent: 90,
      icon: Icons.public,            background: Color(0xFF300900), iconColor: Color(0xFFFFAB91)),
    AvatarDef(id: 'db_19', name: 'Il Prescelto',            unlockType: AvatarUnlockType.collection, collectionKey: 'dragonball', unlockPercent: 95,
      icon: Icons.flare,             background: Color(0xFF1A0500), iconColor: Color(0xFFFDD835)),
    AvatarDef(id: 'db_20', name: "Il Più Forte dell'Universo", unlockType: AvatarUnlockType.collection, collectionKey: 'dragonball', unlockPercent: 100,
      icon: Icons.flare,             background: Color(0xFF1A0500), iconColor: Color(0xFFFDD835)),

    // ── Cardfight!! Vanguard ──────────────────────────────────────────────────
    AvatarDef(id: 'vg_1',  name: 'Curioso di Vanguard',     unlockType: AvatarUnlockType.collection, collectionKey: 'vanguard', unlockPercent: 5,
      icon: Icons.person,            background: Color(0xFF1565C0), iconColor: Color(0xFF90CAF9)),
    AvatarDef(id: 'vg_2',  name: 'Aspirante',               unlockType: AvatarUnlockType.collection, collectionKey: 'vanguard', unlockPercent: 10,
      icon: Icons.person,            background: Color(0xFF1565C0), iconColor: Color(0xFF90CAF9)),
    AvatarDef(id: 'vg_3',  name: 'Combattente Junior',      unlockType: AvatarUnlockType.collection, collectionKey: 'vanguard', unlockPercent: 15,
      icon: Icons.sports_martial_arts, background: Color(0xFF0D47A1), iconColor: Color(0xFFBBDEFB)),
    AvatarDef(id: 'vg_4',  name: 'Combattente',             unlockType: AvatarUnlockType.collection, collectionKey: 'vanguard', unlockPercent: 20,
      icon: Icons.sports_martial_arts, background: Color(0xFF0D47A1), iconColor: Color(0xFFBBDEFB)),
    AvatarDef(id: 'vg_5',  name: 'Cavaliere Emergente',     unlockType: AvatarUnlockType.collection, collectionKey: 'vanguard', unlockPercent: 25,
      icon: Icons.shield,            background: Color(0xFF083880), iconColor: Color(0xFF82B1FF)),
    AvatarDef(id: 'vg_6',  name: 'Cavaliere',               unlockType: AvatarUnlockType.collection, collectionKey: 'vanguard', unlockPercent: 30,
      icon: Icons.shield,            background: Color(0xFF083880), iconColor: Color(0xFF82B1FF)),
    AvatarDef(id: 'vg_7',  name: 'Cavaliere Senior',        unlockType: AvatarUnlockType.collection, collectionKey: 'vanguard', unlockPercent: 35,
      icon: Icons.badge,             background: Color(0xFF052B6B), iconColor: Color(0xFF64B5F6)),
    AvatarDef(id: 'vg_8',  name: "Cavaliere d'Elite",       unlockType: AvatarUnlockType.collection, collectionKey: 'vanguard', unlockPercent: 40,
      icon: Icons.badge,             background: Color(0xFF052B6B), iconColor: Color(0xFF64B5F6)),
    AvatarDef(id: 'vg_9',  name: 'Paladino Junior',         unlockType: AvatarUnlockType.collection, collectionKey: 'vanguard', unlockPercent: 45,
      icon: Icons.security,          background: Color(0xFF021E50), iconColor: Color(0xFF82B1FF)),
    AvatarDef(id: 'vg_10', name: 'Paladino',                unlockType: AvatarUnlockType.collection, collectionKey: 'vanguard', unlockPercent: 50,
      icon: Icons.security,          background: Color(0xFF021E50), iconColor: Color(0xFF82B1FF)),
    AvatarDef(id: 'vg_11', name: 'Cavaliere Platino Junior',unlockType: AvatarUnlockType.collection, collectionKey: 'vanguard', unlockPercent: 55,
      icon: Icons.workspace_premium, background: Color(0xFF001540), iconColor: Color(0xFF64B5F6)),
    AvatarDef(id: 'vg_12', name: 'Cavaliere di Platino',    unlockType: AvatarUnlockType.collection, collectionKey: 'vanguard', unlockPercent: 60,
      icon: Icons.workspace_premium, background: Color(0xFF001540), iconColor: Color(0xFF64B5F6)),
    AvatarDef(id: 'vg_13', name: 'Campione Junior',         unlockType: AvatarUnlockType.collection, collectionKey: 'vanguard', unlockPercent: 65,
      icon: Icons.military_tech,     background: Color(0xFF000D30), iconColor: Color(0xFF90CAF9)),
    AvatarDef(id: 'vg_14', name: 'Campione',                unlockType: AvatarUnlockType.collection, collectionKey: 'vanguard', unlockPercent: 70,
      icon: Icons.military_tech,     background: Color(0xFF000D30), iconColor: Color(0xFF90CAF9)),
    AvatarDef(id: 'vg_15', name: 'Re Emergente',            unlockType: AvatarUnlockType.collection, collectionKey: 'vanguard', unlockPercent: 75,
      icon: Icons.stars,             background: Color(0xFF000820), iconColor: Color(0xFF82B1FF)),
    AvatarDef(id: 'vg_16', name: "Re dell'Avanguardia",     unlockType: AvatarUnlockType.collection, collectionKey: 'vanguard', unlockPercent: 80,
      icon: Icons.stars,             background: Color(0xFF000820), iconColor: Color(0xFF82B1FF)),
    AvatarDef(id: 'vg_17', name: 'Leggenda Emergente',      unlockType: AvatarUnlockType.collection, collectionKey: 'vanguard', unlockPercent: 85,
      icon: Icons.diamond,           background: Color(0xFF000515), iconColor: Color(0xFF64B5F6)),
    AvatarDef(id: 'vg_18', name: 'Leggenda Vanguard',       unlockType: AvatarUnlockType.collection, collectionKey: 'vanguard', unlockPercent: 90,
      icon: Icons.diamond,           background: Color(0xFF000515), iconColor: Color(0xFF64B5F6)),
    AvatarDef(id: 'vg_19', name: 'Imperatore Nascente',     unlockType: AvatarUnlockType.collection, collectionKey: 'vanguard', unlockPercent: 95,
      icon: Icons.auto_awesome,      background: Color(0xFF000051), iconColor: Color(0xFFFDD835)),
    AvatarDef(id: 'vg_20', name: 'Imperatore',              unlockType: AvatarUnlockType.collection, collectionKey: 'vanguard', unlockPercent: 100,
      icon: Icons.auto_awesome,      background: Color(0xFF000051), iconColor: Color(0xFFFDD835)),

    // ── Weiß Schwarz ──────────────────────────────────────────────────────────
    AvatarDef(id: 'ws_1',  name: 'Curioso della Scena',     unlockType: AvatarUnlockType.collection, collectionKey: 'weiss_schwarz', unlockPercent: 5,
      icon: Icons.remove_red_eye,    background: Color(0xFF424242), iconColor: Color(0xFFEEEEEE)),
    AvatarDef(id: 'ws_2',  name: 'Spettatore',              unlockType: AvatarUnlockType.collection, collectionKey: 'weiss_schwarz', unlockPercent: 10,
      icon: Icons.remove_red_eye,    background: Color(0xFF424242), iconColor: Color(0xFFEEEEEE)),
    AvatarDef(id: 'ws_3',  name: 'Artista Junior',          unlockType: AvatarUnlockType.collection, collectionKey: 'weiss_schwarz', unlockPercent: 15,
      icon: Icons.theater_comedy,    background: Color(0xFF363636), iconColor: Color(0xFFF5F5F5)),
    AvatarDef(id: 'ws_4',  name: 'Artista',                 unlockType: AvatarUnlockType.collection, collectionKey: 'weiss_schwarz', unlockPercent: 20,
      icon: Icons.theater_comedy,    background: Color(0xFF363636), iconColor: Color(0xFFF5F5F5)),
    AvatarDef(id: 'ws_5',  name: 'Performer Esperto',       unlockType: AvatarUnlockType.collection, collectionKey: 'weiss_schwarz', unlockPercent: 25,
      icon: Icons.music_note,        background: Color(0xFF2B2B2B), iconColor: Color(0xFFEEEEEE)),
    AvatarDef(id: 'ws_6',  name: 'Performer',               unlockType: AvatarUnlockType.collection, collectionKey: 'weiss_schwarz', unlockPercent: 30,
      icon: Icons.music_note,        background: Color(0xFF2B2B2B), iconColor: Color(0xFFEEEEEE)),
    AvatarDef(id: 'ws_7',  name: 'Idol Emergente',          unlockType: AvatarUnlockType.collection, collectionKey: 'weiss_schwarz', unlockPercent: 35,
      icon: Icons.star_border,       background: Color(0xFF212121), iconColor: Color(0xFFF5F5F5)),
    AvatarDef(id: 'ws_8',  name: 'Idol',                    unlockType: AvatarUnlockType.collection, collectionKey: 'weiss_schwarz', unlockPercent: 40,
      icon: Icons.star_border,       background: Color(0xFF212121), iconColor: Color(0xFFF5F5F5)),
    AvatarDef(id: 'ws_9',  name: 'Protagonista Junior',     unlockType: AvatarUnlockType.collection, collectionKey: 'weiss_schwarz', unlockPercent: 45,
      icon: Icons.stars,             background: Color(0xFF1A1A1A), iconColor: Color(0xFFFFFFFF)),
    AvatarDef(id: 'ws_10', name: 'Protagonista',            unlockType: AvatarUnlockType.collection, collectionKey: 'weiss_schwarz', unlockPercent: 50,
      icon: Icons.stars,             background: Color(0xFF1A1A1A), iconColor: Color(0xFFFFFFFF)),
    AvatarDef(id: 'ws_11', name: 'Star Player Junior',      unlockType: AvatarUnlockType.collection, collectionKey: 'weiss_schwarz', unlockPercent: 55,
      icon: Icons.star,              background: Color(0xFF141414), iconColor: Color(0xFFEEEEEE)),
    AvatarDef(id: 'ws_12', name: 'Star Player',             unlockType: AvatarUnlockType.collection, collectionKey: 'weiss_schwarz', unlockPercent: 60,
      icon: Icons.star,              background: Color(0xFF141414), iconColor: Color(0xFFEEEEEE)),
    AvatarDef(id: 'ws_13', name: 'Campione Stage Junior',   unlockType: AvatarUnlockType.collection, collectionKey: 'weiss_schwarz', unlockPercent: 65,
      icon: Icons.emoji_events,      background: Color(0xFF0E0E0E), iconColor: Color(0xFFF5F5F5)),
    AvatarDef(id: 'ws_14', name: 'Campione Stage',          unlockType: AvatarUnlockType.collection, collectionKey: 'weiss_schwarz', unlockPercent: 70,
      icon: Icons.emoji_events,      background: Color(0xFF0E0E0E), iconColor: Color(0xFFF5F5F5)),
    AvatarDef(id: 'ws_15', name: 'Superstar Junior',        unlockType: AvatarUnlockType.collection, collectionKey: 'weiss_schwarz', unlockPercent: 75,
      icon: Icons.workspace_premium, background: Color(0xFF080808), iconColor: Color(0xFFFFFFFF)),
    AvatarDef(id: 'ws_16', name: 'Superstar',               unlockType: AvatarUnlockType.collection, collectionKey: 'weiss_schwarz', unlockPercent: 80,
      icon: Icons.workspace_premium, background: Color(0xFF080808), iconColor: Color(0xFFFFFFFF)),
    AvatarDef(id: 'ws_17', name: 'Gran Finale Junior',      unlockType: AvatarUnlockType.collection, collectionKey: 'weiss_schwarz', unlockPercent: 85,
      icon: Icons.diamond,           background: Color(0xFF030303), iconColor: Color(0xFFF5F5F5)),
    AvatarDef(id: 'ws_18', name: 'Gran Finale',             unlockType: AvatarUnlockType.collection, collectionKey: 'weiss_schwarz', unlockPercent: 90,
      icon: Icons.diamond,           background: Color(0xFF030303), iconColor: Color(0xFFF5F5F5)),
    AvatarDef(id: 'ws_19', name: 'Stella Nascente',         unlockType: AvatarUnlockType.collection, collectionKey: 'weiss_schwarz', unlockPercent: 95,
      icon: Icons.auto_awesome,      background: Color(0xFF000000), iconColor: Color(0xFFFDD835)),
    AvatarDef(id: 'ws_20', name: 'Leggenda della Scena',    unlockType: AvatarUnlockType.collection, collectionKey: 'weiss_schwarz', unlockPercent: 100,
      icon: Icons.auto_awesome,      background: Color(0xFF000000), iconColor: Color(0xFFFDD835)),

    // ── Final Fantasy TCG ─────────────────────────────────────────────────────
    AvatarDef(id: 'ff_1',  name: 'Curioso di Crystalis',    unlockType: AvatarUnlockType.collection, collectionKey: 'final_fantasy', unlockPercent: 5,
      icon: Icons.person,            background: Color(0xFF006064), iconColor: Color(0xFF80DEEA)),
    AvatarDef(id: 'ff_2',  name: 'Novizio',                  unlockType: AvatarUnlockType.collection, collectionKey: 'final_fantasy', unlockPercent: 10,
      icon: Icons.person,            background: Color(0xFF006064), iconColor: Color(0xFF80DEEA)),
    AvatarDef(id: 'ff_3',  name: 'Guerriero Junior',        unlockType: AvatarUnlockType.collection, collectionKey: 'final_fantasy', unlockPercent: 15,
      icon: Icons.light_mode,        background: Color(0xFF00838F), iconColor: Color(0xFFB2EBF2)),
    AvatarDef(id: 'ff_4',  name: 'Guerriero della Luce',    unlockType: AvatarUnlockType.collection, collectionKey: 'final_fantasy', unlockPercent: 20,
      icon: Icons.light_mode,        background: Color(0xFF00838F), iconColor: Color(0xFFB2EBF2)),
    AvatarDef(id: 'ff_5',  name: 'Cercatore Esperto',       unlockType: AvatarUnlockType.collection, collectionKey: 'final_fantasy', unlockPercent: 25,
      icon: Icons.search,            background: Color(0xFF00737E), iconColor: Color(0xFFB2EBF2)),
    AvatarDef(id: 'ff_6',  name: 'Cercatore di Cristalli',  unlockType: AvatarUnlockType.collection, collectionKey: 'final_fantasy', unlockPercent: 30,
      icon: Icons.search,            background: Color(0xFF00737E), iconColor: Color(0xFFB2EBF2)),
    AvatarDef(id: 'ff_7',  name: 'Custode Junior',          unlockType: AvatarUnlockType.collection, collectionKey: 'final_fantasy', unlockPercent: 35,
      icon: Icons.diamond,           background: Color(0xFF005F69), iconColor: Color(0xFF80DEEA)),
    AvatarDef(id: 'ff_8',  name: 'Custode del Cristallo',   unlockType: AvatarUnlockType.collection, collectionKey: 'final_fantasy', unlockPercent: 40,
      icon: Icons.diamond,           background: Color(0xFF005F69), iconColor: Color(0xFF80DEEA)),
    AvatarDef(id: 'ff_9',  name: 'Campione Junior',         unlockType: AvatarUnlockType.collection, collectionKey: 'final_fantasy', unlockPercent: 45,
      icon: Icons.military_tech,     background: Color(0xFF004D58), iconColor: Color(0xFF80DEEA)),
    AvatarDef(id: 'ff_10', name: 'Campione della Luce',     unlockType: AvatarUnlockType.collection, collectionKey: 'final_fantasy', unlockPercent: 50,
      icon: Icons.military_tech,     background: Color(0xFF004D58), iconColor: Color(0xFF80DEEA)),
    AvatarDef(id: 'ff_11', name: 'Eletto Junior',           unlockType: AvatarUnlockType.collection, collectionKey: 'final_fantasy', unlockPercent: 55,
      icon: Icons.workspace_premium, background: Color(0xFF004D40), iconColor: Color(0xFFB2DFDB)),
    AvatarDef(id: 'ff_12', name: 'Eletto del Destino',      unlockType: AvatarUnlockType.collection, collectionKey: 'final_fantasy', unlockPercent: 60,
      icon: Icons.workspace_premium, background: Color(0xFF004D40), iconColor: Color(0xFFB2DFDB)),
    AvatarDef(id: 'ff_13', name: 'Leggenda Junior',         unlockType: AvatarUnlockType.collection, collectionKey: 'final_fantasy', unlockPercent: 65,
      icon: Icons.auto_awesome,      background: Color(0xFF003B30), iconColor: Color(0xFF80CBC4)),
    AvatarDef(id: 'ff_14', name: 'Leggenda Crystalis',      unlockType: AvatarUnlockType.collection, collectionKey: 'final_fantasy', unlockPercent: 70,
      icon: Icons.auto_awesome,      background: Color(0xFF003B30), iconColor: Color(0xFF80CBC4)),
    AvatarDef(id: 'ff_15', name: 'Campione Nascente',       unlockType: AvatarUnlockType.collection, collectionKey: 'final_fantasy', unlockPercent: 75,
      icon: Icons.stars,             background: Color(0xFF002825), iconColor: Color(0xFF4DB6AC)),
    AvatarDef(id: 'ff_16', name: 'Campione del Mondo',      unlockType: AvatarUnlockType.collection, collectionKey: 'final_fantasy', unlockPercent: 80,
      icon: Icons.stars,             background: Color(0xFF002825), iconColor: Color(0xFF4DB6AC)),
    AvatarDef(id: 'ff_17', name: 'Oscuro Nascente',         unlockType: AvatarUnlockType.collection, collectionKey: 'final_fantasy', unlockPercent: 85,
      icon: Icons.brightness_7,      background: Color(0xFF001A18), iconColor: Color(0xFF26A69A)),
    AvatarDef(id: 'ff_18', name: "L'Oscuro Signore",        unlockType: AvatarUnlockType.collection, collectionKey: 'final_fantasy', unlockPercent: 90,
      icon: Icons.brightness_7,      background: Color(0xFF001A18), iconColor: Color(0xFF26A69A)),
    AvatarDef(id: 'ff_19', name: 'Prescelto Nascente',      unlockType: AvatarUnlockType.collection, collectionKey: 'final_fantasy', unlockPercent: 95,
      icon: Icons.flare,             background: Color(0xFF002B36), iconColor: Color(0xFFFDD835)),
    AvatarDef(id: 'ff_20', name: "L'Eletto",                unlockType: AvatarUnlockType.collection, collectionKey: 'final_fantasy', unlockPercent: 100,
      icon: Icons.flare,             background: Color(0xFF002B36), iconColor: Color(0xFFFDD835)),

    // ── Force of Will ─────────────────────────────────────────────────────────
    AvatarDef(id: 'fow_1',  name: 'Curioso della Volontà',  unlockType: AvatarUnlockType.collection, collectionKey: 'force_of_will', unlockPercent: 5,
      icon: Icons.person,            background: Color(0xFF1B5E20), iconColor: Color(0xFFA5D6A7)),
    AvatarDef(id: 'fow_2',  name: 'Allievo',                 unlockType: AvatarUnlockType.collection, collectionKey: 'force_of_will', unlockPercent: 10,
      icon: Icons.person,            background: Color(0xFF1B5E20), iconColor: Color(0xFFA5D6A7)),
    AvatarDef(id: 'fow_3',  name: 'Utente Junior',           unlockType: AvatarUnlockType.collection, collectionKey: 'force_of_will', unlockPercent: 15,
      icon: Icons.air,               background: Color(0xFF1E6E22), iconColor: Color(0xFFC8E6C9)),
    AvatarDef(id: 'fow_4',  name: 'Utente della Volontà',   unlockType: AvatarUnlockType.collection, collectionKey: 'force_of_will', unlockPercent: 20,
      icon: Icons.air,               background: Color(0xFF1E6E22), iconColor: Color(0xFFC8E6C9)),
    AvatarDef(id: 'fow_5',  name: 'Mago Avanzato',           unlockType: AvatarUnlockType.collection, collectionKey: 'force_of_will', unlockPercent: 25,
      icon: Icons.psychology,        background: Color(0xFF2E7D32), iconColor: Color(0xFFC8E6C9)),
    AvatarDef(id: 'fow_6',  name: 'Mago Novizio',            unlockType: AvatarUnlockType.collection, collectionKey: 'force_of_will', unlockPercent: 30,
      icon: Icons.psychology,        background: Color(0xFF2E7D32), iconColor: Color(0xFFC8E6C9)),
    AvatarDef(id: 'fow_7',  name: 'Mago Esperto',            unlockType: AvatarUnlockType.collection, collectionKey: 'force_of_will', unlockPercent: 35,
      icon: Icons.auto_fix_high,     background: Color(0xFF285E2B), iconColor: Color(0xFFA5D6A7)),
    AvatarDef(id: 'fow_8',  name: 'Mago',                   unlockType: AvatarUnlockType.collection, collectionKey: 'force_of_will', unlockPercent: 40,
      icon: Icons.auto_fix_high,     background: Color(0xFF285E2B), iconColor: Color(0xFFA5D6A7)),
    AvatarDef(id: 'fow_9',  name: 'Sovrano Junior',          unlockType: AvatarUnlockType.collection, collectionKey: 'force_of_will', unlockPercent: 45,
      icon: Icons.account_balance,   background: Color(0xFF33691E), iconColor: Color(0xFFDCEDC8)),
    AvatarDef(id: 'fow_10', name: 'Sovrano',                 unlockType: AvatarUnlockType.collection, collectionKey: 'force_of_will', unlockPercent: 50,
      icon: Icons.account_balance,   background: Color(0xFF33691E), iconColor: Color(0xFFDCEDC8)),
    AvatarDef(id: 'fow_11', name: 'Alto Sovrano Junior',     unlockType: AvatarUnlockType.collection, collectionKey: 'force_of_will', unlockPercent: 55,
      icon: Icons.military_tech,     background: Color(0xFF2A5519), iconColor: Color(0xFFC8E6C9)),
    AvatarDef(id: 'fow_12', name: 'Alto Sovrano',            unlockType: AvatarUnlockType.collection, collectionKey: 'force_of_will', unlockPercent: 60,
      icon: Icons.military_tech,     background: Color(0xFF2A5519), iconColor: Color(0xFFC8E6C9)),
    AvatarDef(id: 'fow_13', name: 'Gran Sovrano Junior',     unlockType: AvatarUnlockType.collection, collectionKey: 'force_of_will', unlockPercent: 65,
      icon: Icons.workspace_premium, background: Color(0xFF1E3F12), iconColor: Color(0xFFA5D6A7)),
    AvatarDef(id: 'fow_14', name: 'Gran Sovrano',            unlockType: AvatarUnlockType.collection, collectionKey: 'force_of_will', unlockPercent: 70,
      icon: Icons.workspace_premium, background: Color(0xFF1E3F12), iconColor: Color(0xFFA5D6A7)),
    AvatarDef(id: 'fow_15', name: 'Signore Junior',          unlockType: AvatarUnlockType.collection, collectionKey: 'force_of_will', unlockPercent: 75,
      icon: Icons.stars,             background: Color(0xFF142A0C), iconColor: Color(0xFF81C784)),
    AvatarDef(id: 'fow_16', name: 'Signore del Tempo',       unlockType: AvatarUnlockType.collection, collectionKey: 'force_of_will', unlockPercent: 80,
      icon: Icons.stars,             background: Color(0xFF142A0C), iconColor: Color(0xFF81C784)),
    AvatarDef(id: 'fow_17', name: 'Custode Junior',          unlockType: AvatarUnlockType.collection, collectionKey: 'force_of_will', unlockPercent: 85,
      icon: Icons.diamond,           background: Color(0xFF0D1A07), iconColor: Color(0xFF66BB6A)),
    AvatarDef(id: 'fow_18', name: "Custode dell'Infinito",   unlockType: AvatarUnlockType.collection, collectionKey: 'force_of_will', unlockPercent: 90,
      icon: Icons.diamond,           background: Color(0xFF0D1A07), iconColor: Color(0xFF66BB6A)),
    AvatarDef(id: 'fow_19', name: 'Vero Custode',            unlockType: AvatarUnlockType.collection, collectionKey: 'force_of_will', unlockPercent: 95,
      icon: Icons.brightness_7,      background: Color(0xFF1A3300), iconColor: Color(0xFFFDD835)),
    AvatarDef(id: 'fow_20', name: 'Vero Sovrano',            unlockType: AvatarUnlockType.collection, collectionKey: 'force_of_will', unlockPercent: 100,
      icon: Icons.brightness_7,      background: Color(0xFF1A3300), iconColor: Color(0xFFFDD835)),

    // ── Battle Spirits Saga ───────────────────────────────────────────────────
    AvatarDef(id: 'bss_1',  name: 'Curioso degli Spiriti',   unlockType: AvatarUnlockType.collection, collectionKey: 'battle_spirits', unlockPercent: 5,
      icon: Icons.person,            background: Color(0xFFB71C1C), iconColor: Color(0xFFFFCDD2)),
    AvatarDef(id: 'bss_2',  name: 'Sfidante',                unlockType: AvatarUnlockType.collection, collectionKey: 'battle_spirits', unlockPercent: 10,
      icon: Icons.person,            background: Color(0xFFB71C1C), iconColor: Color(0xFFFFCDD2)),
    AvatarDef(id: 'bss_3',  name: 'Combattente Junior',      unlockType: AvatarUnlockType.collection, collectionKey: 'battle_spirits', unlockPercent: 15,
      icon: Icons.bolt,              background: Color(0xFFC22020), iconColor: Color(0xFFFF8A80)),
    AvatarDef(id: 'bss_4',  name: 'Combattente',             unlockType: AvatarUnlockType.collection, collectionKey: 'battle_spirits', unlockPercent: 20,
      icon: Icons.bolt,              background: Color(0xFFC22020), iconColor: Color(0xFFFF8A80)),
    AvatarDef(id: 'bss_5',  name: 'Spirito Junior',          unlockType: AvatarUnlockType.collection, collectionKey: 'battle_spirits', unlockPercent: 25,
      icon: Icons.sports_martial_arts, background: Color(0xFFC62828), iconColor: Color(0xFFFF8A80)),
    AvatarDef(id: 'bss_6',  name: 'Spirito in Addestramento',unlockType: AvatarUnlockType.collection, collectionKey: 'battle_spirits', unlockPercent: 30,
      icon: Icons.sports_martial_arts, background: Color(0xFFC62828), iconColor: Color(0xFFFF8A80)),
    AvatarDef(id: 'bss_7',  name: 'Spirito Avanzato',        unlockType: AvatarUnlockType.collection, collectionKey: 'battle_spirits', unlockPercent: 35,
      icon: Icons.electric_bolt,     background: Color(0xFFA01E1E), iconColor: Color(0xFFFF5252)),
    AvatarDef(id: 'bss_8',  name: 'Spirito Battaglia',       unlockType: AvatarUnlockType.collection, collectionKey: 'battle_spirits', unlockPercent: 40,
      icon: Icons.electric_bolt,     background: Color(0xFFA01E1E), iconColor: Color(0xFFFF5252)),
    AvatarDef(id: 'bss_9',  name: 'Maestro Junior',          unlockType: AvatarUnlockType.collection, collectionKey: 'battle_spirits', unlockPercent: 45,
      icon: Icons.military_tech,     background: Color(0xFF8B1919), iconColor: Color(0xFFFF3D00)),
    AvatarDef(id: 'bss_10', name: 'Maestro degli Spiriti',   unlockType: AvatarUnlockType.collection, collectionKey: 'battle_spirits', unlockPercent: 50,
      icon: Icons.military_tech,     background: Color(0xFF8B1919), iconColor: Color(0xFFFF3D00)),
    AvatarDef(id: 'bss_11', name: 'Guardiano Junior',        unlockType: AvatarUnlockType.collection, collectionKey: 'battle_spirits', unlockPercent: 55,
      icon: Icons.security,          background: Color(0xFF750000), iconColor: Color(0xFFFF6E40)),
    AvatarDef(id: 'bss_12', name: 'Guardiano degli Spiriti', unlockType: AvatarUnlockType.collection, collectionKey: 'battle_spirits', unlockPercent: 60,
      icon: Icons.security,          background: Color(0xFF750000), iconColor: Color(0xFFFF6E40)),
    AvatarDef(id: 'bss_13', name: 'Campione Junior',         unlockType: AvatarUnlockType.collection, collectionKey: 'battle_spirits', unlockPercent: 65,
      icon: Icons.workspace_premium, background: Color(0xFF5C0000), iconColor: Color(0xFFFF5252)),
    AvatarDef(id: 'bss_14', name: 'Campione',                unlockType: AvatarUnlockType.collection, collectionKey: 'battle_spirits', unlockPercent: 70,
      icon: Icons.workspace_premium, background: Color(0xFF5C0000), iconColor: Color(0xFFFF5252)),
    AvatarDef(id: 'bss_15', name: 'Gran Campione Junior',    unlockType: AvatarUnlockType.collection, collectionKey: 'battle_spirits', unlockPercent: 75,
      icon: Icons.stars,             background: Color(0xFF450000), iconColor: Color(0xFFFF4040)),
    AvatarDef(id: 'bss_16', name: 'Gran Campione',           unlockType: AvatarUnlockType.collection, collectionKey: 'battle_spirits', unlockPercent: 80,
      icon: Icons.stars,             background: Color(0xFF450000), iconColor: Color(0xFFFF4040)),
    AvatarDef(id: 'bss_17', name: 'Spirito Avanzato Senior', unlockType: AvatarUnlockType.collection, collectionKey: 'battle_spirits', unlockPercent: 85,
      icon: Icons.diamond,           background: Color(0xFF300000), iconColor: Color(0xFFFF6E40)),
    AvatarDef(id: 'bss_18', name: 'Spirito Leggendario',     unlockType: AvatarUnlockType.collection, collectionKey: 'battle_spirits', unlockPercent: 90,
      icon: Icons.diamond,           background: Color(0xFF300000), iconColor: Color(0xFFFF6E40)),
    AvatarDef(id: 'bss_19', name: 'Grande Spirito Junior',   unlockType: AvatarUnlockType.collection, collectionKey: 'battle_spirits', unlockPercent: 95,
      icon: Icons.flash_on,          background: Color(0xFF3B0000), iconColor: Color(0xFFFDD835)),
    AvatarDef(id: 'bss_20', name: 'Grande Spirito',          unlockType: AvatarUnlockType.collection, collectionKey: 'battle_spirits', unlockPercent: 100,
      icon: Icons.flash_on,          background: Color(0xFF3B0000), iconColor: Color(0xFFFDD835)),

    // ── World of Warcraft TCG ─────────────────────────────────────────────────
    AvatarDef(id: 'wow_1',  name: 'Curioso di Azeroth',      unlockType: AvatarUnlockType.collection, collectionKey: 'wow', unlockPercent: 5,
      icon: Icons.person,            background: Color(0xFF4527A0), iconColor: Color(0xFFD1C4E9)),
    AvatarDef(id: 'wow_2',  name: 'Novizio',                 unlockType: AvatarUnlockType.collection, collectionKey: 'wow', unlockPercent: 10,
      icon: Icons.person,            background: Color(0xFF4527A0), iconColor: Color(0xFFD1C4E9)),
    AvatarDef(id: 'wow_3',  name: 'Avventuriero Junior',     unlockType: AvatarUnlockType.collection, collectionKey: 'wow', unlockPercent: 15,
      icon: Icons.explore,           background: Color(0xFF3E239A), iconColor: Color(0xFFC5CAE9)),
    AvatarDef(id: 'wow_4',  name: 'Avventuriero',            unlockType: AvatarUnlockType.collection, collectionKey: 'wow', unlockPercent: 20,
      icon: Icons.explore,           background: Color(0xFF3E239A), iconColor: Color(0xFFC5CAE9)),
    AvatarDef(id: 'wow_5',  name: 'Eroe Junior',             unlockType: AvatarUnlockType.collection, collectionKey: 'wow', unlockPercent: 25,
      icon: Icons.shield,            background: Color(0xFF311B92), iconColor: Color(0xFFEDE7F6)),
    AvatarDef(id: 'wow_6',  name: 'Eroe',                   unlockType: AvatarUnlockType.collection, collectionKey: 'wow', unlockPercent: 30,
      icon: Icons.shield,            background: Color(0xFF311B92), iconColor: Color(0xFFEDE7F6)),
    AvatarDef(id: 'wow_7',  name: 'Cavaliere Junior',        unlockType: AvatarUnlockType.collection, collectionKey: 'wow', unlockPercent: 35,
      icon: Icons.military_tech,     background: Color(0xFF27158A), iconColor: Color(0xFFD1C4E9)),
    AvatarDef(id: 'wow_8',  name: 'Cavaliere',               unlockType: AvatarUnlockType.collection, collectionKey: 'wow', unlockPercent: 40,
      icon: Icons.military_tech,     background: Color(0xFF27158A), iconColor: Color(0xFFD1C4E9)),
    AvatarDef(id: 'wow_9',  name: 'Campione Junior',         unlockType: AvatarUnlockType.collection, collectionKey: 'wow', unlockPercent: 45,
      icon: Icons.emoji_events,      background: Color(0xFF1E1079), iconColor: Color(0xFFC5CAE9)),
    AvatarDef(id: 'wow_10', name: 'Campione',                unlockType: AvatarUnlockType.collection, collectionKey: 'wow', unlockPercent: 50,
      icon: Icons.emoji_events,      background: Color(0xFF1E1079), iconColor: Color(0xFFC5CAE9)),
    AvatarDef(id: 'wow_11', name: 'Paladino Junior',         unlockType: AvatarUnlockType.collection, collectionKey: 'wow', unlockPercent: 55,
      icon: Icons.workspace_premium, background: Color(0xFF1A0D6B), iconColor: Color(0xFFB39DDB)),
    AvatarDef(id: 'wow_12', name: 'Paladino Sacro',          unlockType: AvatarUnlockType.collection, collectionKey: 'wow', unlockPercent: 60,
      icon: Icons.workspace_premium, background: Color(0xFF1A0D6B), iconColor: Color(0xFFB39DDB)),
    AvatarDef(id: 'wow_13', name: 'Comandante Junior',       unlockType: AvatarUnlockType.collection, collectionKey: 'wow', unlockPercent: 65,
      icon: Icons.stars,             background: Color(0xFF140A50), iconColor: Color(0xFFD1C4E9)),
    AvatarDef(id: 'wow_14', name: 'Comandante di Gilda',     unlockType: AvatarUnlockType.collection, collectionKey: 'wow', unlockPercent: 70,
      icon: Icons.stars,             background: Color(0xFF140A50), iconColor: Color(0xFFD1C4E9)),
    AvatarDef(id: 'wow_15', name: 'Campione Senior',         unlockType: AvatarUnlockType.collection, collectionKey: 'wow', unlockPercent: 75,
      icon: Icons.diamond,           background: Color(0xFF0E073A), iconColor: Color(0xFFC5CAE9)),
    AvatarDef(id: 'wow_16', name: 'Campione di Azeroth',     unlockType: AvatarUnlockType.collection, collectionKey: 'wow', unlockPercent: 80,
      icon: Icons.diamond,           background: Color(0xFF0E073A), iconColor: Color(0xFFC5CAE9)),
    AvatarDef(id: 'wow_17', name: 'Leggendario Junior',      unlockType: AvatarUnlockType.collection, collectionKey: 'wow', unlockPercent: 85,
      icon: Icons.auto_awesome,      background: Color(0xFF080425), iconColor: Color(0xFFB39DDB)),
    AvatarDef(id: 'wow_18', name: 'Leggendario',             unlockType: AvatarUnlockType.collection, collectionKey: 'wow', unlockPercent: 90,
      icon: Icons.auto_awesome,      background: Color(0xFF080425), iconColor: Color(0xFFB39DDB)),
    AvatarDef(id: 'wow_19', name: 'Salvatore Junior',        unlockType: AvatarUnlockType.collection, collectionKey: 'wow', unlockPercent: 95,
      icon: Icons.brightness_7,      background: Color(0xFF0D0026), iconColor: Color(0xFFFDD835)),
    AvatarDef(id: 'wow_20', name: 'Il Salvatore di Azeroth', unlockType: AvatarUnlockType.collection, collectionKey: 'wow', unlockPercent: 100,
      icon: Icons.brightness_7,      background: Color(0xFF0D0026), iconColor: Color(0xFFFDD835)),

    // ── Star Wars Destiny ─────────────────────────────────────────────────────
    AvatarDef(id: 'swd_1',  name: 'Curioso della Forza',     unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_destiny', unlockPercent: 5,
      icon: Icons.person,            background: Color(0xFF263238), iconColor: Color(0xFFB0BEC5)),
    AvatarDef(id: 'swd_2',  name: 'Civile',                  unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_destiny', unlockPercent: 10,
      icon: Icons.person,            background: Color(0xFF263238), iconColor: Color(0xFFB0BEC5)),
    AvatarDef(id: 'swd_3',  name: 'Padawan Junior',          unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_destiny', unlockPercent: 15,
      icon: Icons.psychology,        background: Color(0xFF1E2B30), iconColor: Color(0xFFCFD8DC)),
    AvatarDef(id: 'swd_4',  name: 'Padawan',                 unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_destiny', unlockPercent: 20,
      icon: Icons.psychology,        background: Color(0xFF1E2B30), iconColor: Color(0xFFCFD8DC)),
    AvatarDef(id: 'swd_5',  name: 'Soldato Esperto',         unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_destiny', unlockPercent: 25,
      icon: Icons.security,          background: Color(0xFF192227), iconColor: Color(0xFFCFD8DC)),
    AvatarDef(id: 'swd_6',  name: 'Soldato della Repubblica',unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_destiny', unlockPercent: 30,
      icon: Icons.security,          background: Color(0xFF192227), iconColor: Color(0xFFCFD8DC)),
    AvatarDef(id: 'swd_7',  name: 'Cavaliere Junior',        unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_destiny', unlockPercent: 35,
      icon: Icons.star,              background: Color(0xFF14191E), iconColor: Color(0xFFECEFF1)),
    AvatarDef(id: 'swd_8',  name: 'Cavaliere Jedi',          unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_destiny', unlockPercent: 40,
      icon: Icons.star,              background: Color(0xFF14191E), iconColor: Color(0xFFECEFF1)),
    AvatarDef(id: 'swd_9',  name: 'Maestro Junior',          unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_destiny', unlockPercent: 45,
      icon: Icons.auto_awesome,      background: Color(0xFF0F1215), iconColor: Color(0xFF80DEEA)),
    AvatarDef(id: 'swd_10', name: 'Maestro Jedi',            unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_destiny', unlockPercent: 50,
      icon: Icons.auto_awesome,      background: Color(0xFF0F1215), iconColor: Color(0xFF80DEEA)),
    AvatarDef(id: 'swd_11', name: 'Generale Junior',         unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_destiny', unlockPercent: 55,
      icon: Icons.military_tech,     background: Color(0xFF0B0E10), iconColor: Color(0xFF80DEEA)),
    AvatarDef(id: 'swd_12', name: 'Generale',                unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_destiny', unlockPercent: 60,
      icon: Icons.military_tech,     background: Color(0xFF0B0E10), iconColor: Color(0xFF80DEEA)),
    AvatarDef(id: 'swd_13', name: 'Gran Maestro Junior',     unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_destiny', unlockPercent: 65,
      icon: Icons.workspace_premium, background: Color(0xFF080A0C), iconColor: Color(0xFFB0BEC5)),
    AvatarDef(id: 'swd_14', name: 'Gran Maestro',            unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_destiny', unlockPercent: 70,
      icon: Icons.workspace_premium, background: Color(0xFF080A0C), iconColor: Color(0xFFB0BEC5)),
    AvatarDef(id: 'swd_15', name: 'Guardiano Junior',        unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_destiny', unlockPercent: 75,
      icon: Icons.stars,             background: Color(0xFF060809), iconColor: Color(0xFFECEFF1)),
    AvatarDef(id: 'swd_16', name: 'Guardiano della Galassia',unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_destiny', unlockPercent: 80,
      icon: Icons.stars,             background: Color(0xFF060809), iconColor: Color(0xFFECEFF1)),
    AvatarDef(id: 'swd_17', name: 'Campione Junior',         unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_destiny', unlockPercent: 85,
      icon: Icons.diamond,           background: Color(0xFF040506), iconColor: Color(0xFFCFD8DC)),
    AvatarDef(id: 'swd_18', name: 'Campione della Forza',    unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_destiny', unlockPercent: 90,
      icon: Icons.diamond,           background: Color(0xFF040506), iconColor: Color(0xFFCFD8DC)),
    AvatarDef(id: 'swd_19', name: 'Maestro Nascente',        unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_destiny', unlockPercent: 95,
      icon: Icons.brightness_7,      background: Color(0xFF060F12), iconColor: Color(0xFFFDD835)),
    AvatarDef(id: 'swd_20', name: 'Maestro della Forza',     unlockType: AvatarUnlockType.collection, collectionKey: 'starwars_destiny', unlockPercent: 100,
      icon: Icons.brightness_7,      background: Color(0xFF060F12), iconColor: Color(0xFFFDD835)),

    // ── Dragoborne ────────────────────────────────────────────────────────────
    AvatarDef(id: 'drag_1',  name: 'Curioso dei Draghi',     unlockType: AvatarUnlockType.collection, collectionKey: 'dragoborne', unlockPercent: 5,
      icon: Icons.person,            background: Color(0xFFBF360C), iconColor: Color(0xFFFFAB91)),
    AvatarDef(id: 'drag_2',  name: 'Aspirante',              unlockType: AvatarUnlockType.collection, collectionKey: 'dragoborne', unlockPercent: 10,
      icon: Icons.person,            background: Color(0xFFBF360C), iconColor: Color(0xFFFFAB91)),
    AvatarDef(id: 'drag_3',  name: 'Addestratore Junior',    unlockType: AvatarUnlockType.collection, collectionKey: 'dragoborne', unlockPercent: 15,
      icon: Icons.local_fire_department, background: Color(0xFFA82E08), iconColor: Color(0xFFFF8A65)),
    AvatarDef(id: 'drag_4',  name: 'Addestratore',           unlockType: AvatarUnlockType.collection, collectionKey: 'dragoborne', unlockPercent: 20,
      icon: Icons.local_fire_department, background: Color(0xFFA82E08), iconColor: Color(0xFFFF8A65)),
    AvatarDef(id: 'drag_5',  name: 'Cavaliere Junior',       unlockType: AvatarUnlockType.collection, collectionKey: 'dragoborne', unlockPercent: 25,
      icon: Icons.shield,            background: Color(0xFF8A2506), iconColor: Color(0xFFFF6E40)),
    AvatarDef(id: 'drag_6',  name: 'Cavaliere dei Draghi',   unlockType: AvatarUnlockType.collection, collectionKey: 'dragoborne', unlockPercent: 30,
      icon: Icons.shield,            background: Color(0xFF8A2506), iconColor: Color(0xFFFF6E40)),
    AvatarDef(id: 'drag_7',  name: 'Signore Junior',         unlockType: AvatarUnlockType.collection, collectionKey: 'dragoborne', unlockPercent: 35,
      icon: Icons.security,          background: Color(0xFF701E04), iconColor: Color(0xFFFF5722)),
    AvatarDef(id: 'drag_8',  name: 'Signore dei Draghi',     unlockType: AvatarUnlockType.collection, collectionKey: 'dragoborne', unlockPercent: 40,
      icon: Icons.security,          background: Color(0xFF701E04), iconColor: Color(0xFFFF5722)),
    AvatarDef(id: 'drag_9',  name: 'Guardiano Junior',       unlockType: AvatarUnlockType.collection, collectionKey: 'dragoborne', unlockPercent: 45,
      icon: Icons.pets,              background: Color(0xFF5A1503), iconColor: Color(0xFFFF7043)),
    AvatarDef(id: 'drag_10', name: 'Guardiano dei Draghi',   unlockType: AvatarUnlockType.collection, collectionKey: 'dragoborne', unlockPercent: 50,
      icon: Icons.pets,              background: Color(0xFF5A1503), iconColor: Color(0xFFFF7043)),
    AvatarDef(id: 'drag_11', name: 'Campione Junior',        unlockType: AvatarUnlockType.collection, collectionKey: 'dragoborne', unlockPercent: 55,
      icon: Icons.military_tech,     background: Color(0xFF4E0000), iconColor: Color(0xFFFF6E40)),
    AvatarDef(id: 'drag_12', name: 'Campione dei Draghi',    unlockType: AvatarUnlockType.collection, collectionKey: 'dragoborne', unlockPercent: 60,
      icon: Icons.military_tech,     background: Color(0xFF4E0000), iconColor: Color(0xFFFF6E40)),
    AvatarDef(id: 'drag_13', name: 'Maestro Junior',         unlockType: AvatarUnlockType.collection, collectionKey: 'dragoborne', unlockPercent: 65,
      icon: Icons.workspace_premium, background: Color(0xFF3B0000), iconColor: Color(0xFFFF5252)),
    AvatarDef(id: 'drag_14', name: 'Maestro dei Draghi',     unlockType: AvatarUnlockType.collection, collectionKey: 'dragoborne', unlockPercent: 70,
      icon: Icons.workspace_premium, background: Color(0xFF3B0000), iconColor: Color(0xFFFF5252)),
    AvatarDef(id: 'drag_15', name: 'Antico Junior',          unlockType: AvatarUnlockType.collection, collectionKey: 'dragoborne', unlockPercent: 75,
      icon: Icons.diamond,           background: Color(0xFF2A0000), iconColor: Color(0xFFFF6E40)),
    AvatarDef(id: 'drag_16', name: 'Antico Custode',         unlockType: AvatarUnlockType.collection, collectionKey: 'dragoborne', unlockPercent: 80,
      icon: Icons.diamond,           background: Color(0xFF2A0000), iconColor: Color(0xFFFF6E40)),
    AvatarDef(id: 'drag_17', name: 'Dio Nascente',           unlockType: AvatarUnlockType.collection, collectionKey: 'dragoborne', unlockPercent: 85,
      icon: Icons.stars,             background: Color(0xFF1A0000), iconColor: Color(0xFFFFAB91)),
    AvatarDef(id: 'drag_18', name: 'Dio dei Draghi',         unlockType: AvatarUnlockType.collection, collectionKey: 'dragoborne', unlockPercent: 90,
      icon: Icons.stars,             background: Color(0xFF1A0000), iconColor: Color(0xFFFFAB91)),
    AvatarDef(id: 'drag_19', name: 'Imperatore Nascente',    unlockType: AvatarUnlockType.collection, collectionKey: 'dragoborne', unlockPercent: 95,
      icon: Icons.auto_awesome,      background: Color(0xFF1A0000), iconColor: Color(0xFFFDD835)),
    AvatarDef(id: 'drag_20', name: 'Imperatore dei Draghi',  unlockType: AvatarUnlockType.collection, collectionKey: 'dragoborne', unlockPercent: 100,
      icon: Icons.auto_awesome,      background: Color(0xFF1A0000), iconColor: Color(0xFFFDD835)),

    // ── My Little Pony CCG ────────────────────────────────────────────────────
    AvatarDef(id: 'mlp_1',  name: 'Curioso dei Pony',        unlockType: AvatarUnlockType.collection, collectionKey: 'little_pony', unlockPercent: 5,
      icon: Icons.favorite,          background: Color(0xFFAD1457), iconColor: Color(0xFFF48FB1)),
    AvatarDef(id: 'mlp_2',  name: 'Amico dei Pony',          unlockType: AvatarUnlockType.collection, collectionKey: 'little_pony', unlockPercent: 10,
      icon: Icons.favorite,          background: Color(0xFFAD1457), iconColor: Color(0xFFF48FB1)),
    AvatarDef(id: 'mlp_3',  name: 'Abitante Junior',         unlockType: AvatarUnlockType.collection, collectionKey: 'little_pony', unlockPercent: 15,
      icon: Icons.home,              background: Color(0xFF9C1150), iconColor: Color(0xFFF8BBD9)),
    AvatarDef(id: 'mlp_4',  name: 'Abitante di Ponyville',   unlockType: AvatarUnlockType.collection, collectionKey: 'little_pony', unlockPercent: 20,
      icon: Icons.home,              background: Color(0xFF9C1150), iconColor: Color(0xFFF8BBD9)),
    AvatarDef(id: 'mlp_5',  name: 'Unicorno Junior',         unlockType: AvatarUnlockType.collection, collectionKey: 'little_pony', unlockPercent: 25,
      icon: Icons.auto_fix_high,     background: Color(0xFF880E4F), iconColor: Color(0xFFF8BBD9)),
    AvatarDef(id: 'mlp_6',  name: 'Apprendista Unicorno',    unlockType: AvatarUnlockType.collection, collectionKey: 'little_pony', unlockPercent: 30,
      icon: Icons.auto_fix_high,     background: Color(0xFF880E4F), iconColor: Color(0xFFF8BBD9)),
    AvatarDef(id: 'mlp_7',  name: 'Portatore Junior',        unlockType: AvatarUnlockType.collection, collectionKey: 'little_pony', unlockPercent: 35,
      icon: Icons.brightness_7,      background: Color(0xFF720C42), iconColor: Color(0xFFF48FB1)),
    AvatarDef(id: 'mlp_8',  name: "Portatore dell'Elemento", unlockType: AvatarUnlockType.collection, collectionKey: 'little_pony', unlockPercent: 40,
      icon: Icons.brightness_7,      background: Color(0xFF720C42), iconColor: Color(0xFFF48FB1)),
    AvatarDef(id: 'mlp_9',  name: 'Guardiano Junior',        unlockType: AvatarUnlockType.collection, collectionKey: 'little_pony', unlockPercent: 45,
      icon: Icons.shield,            background: Color(0xFF5C0A35), iconColor: Color(0xFFF06292)),
    AvatarDef(id: 'mlp_10', name: "Guardiano dell'Amicizia", unlockType: AvatarUnlockType.collection, collectionKey: 'little_pony', unlockPercent: 50,
      icon: Icons.shield,            background: Color(0xFF5C0A35), iconColor: Color(0xFFF06292)),
    AvatarDef(id: 'mlp_11', name: 'Campione Junior',         unlockType: AvatarUnlockType.collection, collectionKey: 'little_pony', unlockPercent: 55,
      icon: Icons.military_tech,     background: Color(0xFF560027), iconColor: Color(0xFFFF80AB)),
    AvatarDef(id: 'mlp_12', name: "Campione dell'Armonia",   unlockType: AvatarUnlockType.collection, collectionKey: 'little_pony', unlockPercent: 60,
      icon: Icons.military_tech,     background: Color(0xFF560027), iconColor: Color(0xFFFF80AB)),
    AvatarDef(id: 'mlp_13', name: 'Principessa Junior',      unlockType: AvatarUnlockType.collection, collectionKey: 'little_pony', unlockPercent: 65,
      icon: Icons.stars,             background: Color(0xFF42001E), iconColor: Color(0xFFF48FB1)),
    AvatarDef(id: 'mlp_14', name: 'Principessa',             unlockType: AvatarUnlockType.collection, collectionKey: 'little_pony', unlockPercent: 70,
      icon: Icons.stars,             background: Color(0xFF42001E), iconColor: Color(0xFFF48FB1)),
    AvatarDef(id: 'mlp_15', name: 'Alicorno Junior',         unlockType: AvatarUnlockType.collection, collectionKey: 'little_pony', unlockPercent: 75,
      icon: Icons.diamond,           background: Color(0xFF2D0015), iconColor: Color(0xFFFF80AB)),
    AvatarDef(id: 'mlp_16', name: 'Alicorno',                unlockType: AvatarUnlockType.collection, collectionKey: 'little_pony', unlockPercent: 80,
      icon: Icons.diamond,           background: Color(0xFF2D0015), iconColor: Color(0xFFFF80AB)),
    AvatarDef(id: 'mlp_17', name: 'Custode Junior',          unlockType: AvatarUnlockType.collection, collectionKey: 'little_pony', unlockPercent: 85,
      icon: Icons.auto_awesome,      background: Color(0xFF1A000C), iconColor: Color(0xFFF06292)),
    AvatarDef(id: 'mlp_18', name: 'Custode della Magia',     unlockType: AvatarUnlockType.collection, collectionKey: 'little_pony', unlockPercent: 90,
      icon: Icons.auto_awesome,      background: Color(0xFF1A000C), iconColor: Color(0xFFF06292)),
    AvatarDef(id: 'mlp_19', name: 'Celestia Nascente',       unlockType: AvatarUnlockType.collection, collectionKey: 'little_pony', unlockPercent: 95,
      icon: Icons.flare,             background: Color(0xFF2D0015), iconColor: Color(0xFFFDD835)),
    AvatarDef(id: 'mlp_20', name: 'Principessa Celestia',    unlockType: AvatarUnlockType.collection, collectionKey: 'little_pony', unlockPercent: 100,
      icon: Icons.flare,             background: Color(0xFF2D0015), iconColor: Color(0xFFFDD835)),

    // ── The Spoils ────────────────────────────────────────────────────────────
    AvatarDef(id: 'ts_1',  name: 'Curioso del Mercato',      unlockType: AvatarUnlockType.collection, collectionKey: 'the_spoils', unlockPercent: 5,
      icon: Icons.search,            background: Color(0xFF4E342E), iconColor: Color(0xFFBCAAA4)),
    AvatarDef(id: 'ts_2',  name: 'Ricercatore',              unlockType: AvatarUnlockType.collection, collectionKey: 'the_spoils', unlockPercent: 10,
      icon: Icons.search,            background: Color(0xFF4E342E), iconColor: Color(0xFFBCAAA4)),
    AvatarDef(id: 'ts_3',  name: 'Commerciante Junior',      unlockType: AvatarUnlockType.collection, collectionKey: 'the_spoils', unlockPercent: 15,
      icon: Icons.shopping_bag,      background: Color(0xFF6D4C41), iconColor: Color(0xFFD7CCC8)),
    AvatarDef(id: 'ts_4',  name: 'Commerciante',             unlockType: AvatarUnlockType.collection, collectionKey: 'the_spoils', unlockPercent: 20,
      icon: Icons.shopping_bag,      background: Color(0xFF6D4C41), iconColor: Color(0xFFD7CCC8)),
    AvatarDef(id: 'ts_5',  name: 'Mercante Junior',          unlockType: AvatarUnlockType.collection, collectionKey: 'the_spoils', unlockPercent: 25,
      icon: Icons.storefront,        background: Color(0xFFF57F17), iconColor: Color(0xFFFFF9C4)),
    AvatarDef(id: 'ts_6',  name: 'Mercante',                 unlockType: AvatarUnlockType.collection, collectionKey: 'the_spoils', unlockPercent: 30,
      icon: Icons.storefront,        background: Color(0xFFF57F17), iconColor: Color(0xFFFFF9C4)),
    AvatarDef(id: 'ts_7',  name: 'Negoziante Junior',        unlockType: AvatarUnlockType.collection, collectionKey: 'the_spoils', unlockPercent: 35,
      icon: Icons.account_balance,   background: Color(0xFFE65100), iconColor: Color(0xFFFFECB3)),
    AvatarDef(id: 'ts_8',  name: 'Negoziante',               unlockType: AvatarUnlockType.collection, collectionKey: 'the_spoils', unlockPercent: 40,
      icon: Icons.account_balance,   background: Color(0xFFE65100), iconColor: Color(0xFFFFECB3)),
    AvatarDef(id: 'ts_9',  name: 'Affarista Junior',         unlockType: AvatarUnlockType.collection, collectionKey: 'the_spoils', unlockPercent: 45,
      icon: Icons.work,              background: Color(0xFFC84B00), iconColor: Color(0xFFFFE082)),
    AvatarDef(id: 'ts_10', name: 'Affarista',                unlockType: AvatarUnlockType.collection, collectionKey: 'the_spoils', unlockPercent: 50,
      icon: Icons.work,              background: Color(0xFFC84B00), iconColor: Color(0xFFFFE082)),
    AvatarDef(id: 'ts_11', name: 'Tycoon Junior',            unlockType: AvatarUnlockType.collection, collectionKey: 'the_spoils', unlockPercent: 55,
      icon: Icons.workspace_premium, background: Color(0xFFA83D00), iconColor: Color(0xFFFFCC80)),
    AvatarDef(id: 'ts_12', name: 'Tycoon',                   unlockType: AvatarUnlockType.collection, collectionKey: 'the_spoils', unlockPercent: 60,
      icon: Icons.workspace_premium, background: Color(0xFFA83D00), iconColor: Color(0xFFFFCC80)),
    AvatarDef(id: 'ts_13', name: 'Magnate Junior',           unlockType: AvatarUnlockType.collection, collectionKey: 'the_spoils', unlockPercent: 65,
      icon: Icons.military_tech,     background: Color(0xFF8A3200), iconColor: Color(0xFFFFB74D)),
    AvatarDef(id: 'ts_14', name: 'Magnate',                  unlockType: AvatarUnlockType.collection, collectionKey: 'the_spoils', unlockPercent: 70,
      icon: Icons.military_tech,     background: Color(0xFF8A3200), iconColor: Color(0xFFFFB74D)),
    AvatarDef(id: 'ts_15', name: 'Barone Junior',            unlockType: AvatarUnlockType.collection, collectionKey: 'the_spoils', unlockPercent: 75,
      icon: Icons.diamond,           background: Color(0xFF6D2800), iconColor: Color(0xFFFFA726)),
    AvatarDef(id: 'ts_16', name: 'Barone della Ricchezza',   unlockType: AvatarUnlockType.collection, collectionKey: 'the_spoils', unlockPercent: 80,
      icon: Icons.diamond,           background: Color(0xFF6D2800), iconColor: Color(0xFFFFA726)),
    AvatarDef(id: 'ts_17', name: 'Signore Junior',           unlockType: AvatarUnlockType.collection, collectionKey: 'the_spoils', unlockPercent: 85,
      icon: Icons.stars,             background: Color(0xFF4E1D00), iconColor: Color(0xFFFFCC80)),
    AvatarDef(id: 'ts_18', name: 'Signore del Mercato',      unlockType: AvatarUnlockType.collection, collectionKey: 'the_spoils', unlockPercent: 90,
      icon: Icons.stars,             background: Color(0xFF4E1D00), iconColor: Color(0xFFFFCC80)),
    AvatarDef(id: 'ts_19', name: 'Grande Mercante',          unlockType: AvatarUnlockType.collection, collectionKey: 'the_spoils', unlockPercent: 95,
      icon: Icons.auto_awesome,      background: Color(0xFF3E1500), iconColor: Color(0xFFFDD835)),
    AvatarDef(id: 'ts_20', name: 'Signore dei Tesori',       unlockType: AvatarUnlockType.collection, collectionKey: 'the_spoils', unlockPercent: 100,
      icon: Icons.auto_awesome,      background: Color(0xFF3E1500), iconColor: Color(0xFFFDD835)),
  ];

  /// Emette il nuovo livello ogni volta che l'utente sale di livello.
  final _levelUpController = StreamController<int>.broadcast();
  Stream<int> get onLevelUp => _levelUpController.stream;

  // ─── Calcoli statici ──────────────────────────────────────────────────────

  static int levelFromXp(int xp) {
    int level = 1;
    for (int i = 1; i < levelThresholds.length; i++) {
      if (xp >= levelThresholds[i]) {
        level = i + 1;
      } else {
        break;
      }
    }
    return level;
  }

  /// Progresso [0.0, 1.0] all'interno del livello corrente.
  static double levelProgress(int xp) {
    final level = levelFromXp(xp);
    final nextIdx = level;
    if (nextIdx >= levelThresholds.length) return 1.0;
    final currentLevelXp = levelThresholds[level - 1];
    final nextLevelXp = levelThresholds[nextIdx];
    return (xp - currentLevelXp) / (nextLevelXp - currentLevelXp);
  }

  static int xpToNextLevel(int xp) {
    final level = levelFromXp(xp);
    if (level >= levelThresholds.length) return 0; // Livello massimo (100)
    return levelThresholds[level] - xp;
  }

  /// XP da assegnare in base alla rarità della carta.
  static int xpForRarity(String rarity) {
    final r = rarity.toLowerCase();
    if (r.contains('ghost') || r.contains('prismatic')) return 40;
    if (r.contains('secret') || r.contains('ultimate') || r.contains('platinum')) return 30;
    if (r.contains('ultra')) return 25;
    if (r.contains('super')) return 20;
    if (r.contains('rare')) return 10;
    return 5;
  }

  /// Avatar sbloccati dato il livello account e le completions delle collezioni.
  static List<AvatarDef> unlockedAvatars(int level, Map<String, double> completions) =>
      avatars.where((a) => a.isUnlocked(level, completions)).toList();

  // ─── Stato locale ─────────────────────────────────────────────────────────

  Future<int> getCurrentXp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_xpKey) ?? 0;
  }

  /// Imposta l'XP se il valore passato è superiore a quello attuale.
  /// Usato per il backfill iniziale dalle carte già presenti in collezione.
  Future<void> setXpIfHigher(int xp) async {
    final prefs = await SharedPreferences.getInstance();
    final currentXp = prefs.getInt(_xpKey) ?? 0;
    if (xp <= currentXp) return;
    final oldLevel = levelFromXp(currentXp);
    final newLevel = levelFromXp(xp);
    await prefs.setInt(_xpKey, xp);
    _syncXpToFirestore(xp);
    if (newLevel > oldLevel) _levelUpController.add(newLevel);
  }

  Future<void> awardXp(int amount) async {
    final prefs = await SharedPreferences.getInstance();
    final oldXp = prefs.getInt(_xpKey) ?? 0;
    final oldLevel = levelFromXp(oldXp);
    final newXp = oldXp + amount;
    final newLevel = levelFromXp(newXp);
    await prefs.setInt(_xpKey, newXp);
    _syncXpToFirestore(newXp);
    if (newLevel > oldLevel) _levelUpController.add(newLevel);
  }

  void _syncXpToFirestore(int xp) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({'xp': xp}, SetOptions(merge: true))
        .catchError((_) {});
  }

  /// Sincronizza XP e avatar selezionato da Firestore (al più una volta ogni 24h).
  Future<void> syncFromFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Evita letture Firestore superflue: sync solo se il dato è stale (> 24h)
      final lastSynced = prefs.getString('xp_synced_at_$uid');
      if (lastSynced != null) {
        final last = DateTime.tryParse(lastSynced);
        if (last != null && DateTime.now().difference(last).inHours < 24) return;
      }
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 8));
      final data = doc.data();
      if (data == null) return;
      final remoteXp = data['xp'] as int? ?? 0;
      final remoteAvatarId = data['selectedAvatarId'] as String?;
      final localXp = prefs.getInt(_xpKey) ?? 0;
      if (remoteXp > localXp) await prefs.setInt(_xpKey, remoteXp);
      if (remoteAvatarId != null && prefs.getString(_avatarKey) == null) {
        await prefs.setString(_avatarKey, remoteAvatarId);
      }
      await prefs.setString('xp_synced_at_$uid', DateTime.now().toIso8601String());
    } catch (_) {}
  }

  Future<String?> getSelectedAvatarId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_avatarKey);
  }

  Future<void> clearSelectedAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_avatarKey);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'selectedAvatarId': null}, SetOptions(merge: true))
          .catchError((_) {});
    }
  }

  Future<void> setSelectedAvatarId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_avatarKey, id);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'selectedAvatarId': id}, SetOptions(merge: true))
          .catchError((_) {});
    }
  }
}
