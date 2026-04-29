import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/services/xp_service.dart';

void main() {
  // Tutti i test usano solo metodi STATICI / puri — zero Firebase, zero SharedPreferences

  group('XpService - levelFromXp', () {
    test('0 XP → livello 1', () => expect(XpService.levelFromXp(0), 1));
    test('76 XP → livello 1 (sotto la soglia per liv.2)', () {
      expect(XpService.levelFromXp(76), 1);
    });
    test('77 XP → livello 2 (esattamente sulla soglia)', () {
      expect(XpService.levelFromXp(77), 2);
    });
    test('305 XP → livello 2', () => expect(XpService.levelFromXp(305), 2));
    test('306 XP → livello 3', () => expect(XpService.levelFromXp(306), 3));
    test('750000 XP → livello 100 (massimo)', () {
      expect(XpService.levelFromXp(750000), 100);
    });
    test('XP sopra il massimo → livello 100 (non eccede)', () {
      expect(XpService.levelFromXp(999999), 100);
    });
    test('livello cresce monotonicamente con XP', () {
      int prev = XpService.levelFromXp(0);
      for (final threshold in XpService.levelThresholds) {
        final lvl = XpService.levelFromXp(threshold);
        expect(lvl, greaterThanOrEqualTo(prev));
        prev = lvl;
      }
    });
    test('ogni soglia porta esattamente al livello atteso', () {
      for (int i = 1; i < XpService.levelThresholds.length; i++) {
        final xp = XpService.levelThresholds[i];
        final expectedLevel = i + 1;
        expect(XpService.levelFromXp(xp), expectedLevel,
            reason: 'xp=$xp dovrebbe essere livello $expectedLevel');
      }
    });
  });

  group('XpService - levelProgress', () {
    test('0 XP → 0.0 (nessun progresso)', () {
      expect(XpService.levelProgress(0), 0.0);
    });

    test('metà del primo livello → ~0.5', () {
      // Livello 1: 0→77, metà = 38
      final progress = XpService.levelProgress(38);
      expect(progress, closeTo(38 / 77, 0.001));
    });

    test('esattamente sulla soglia del liv.2 → 0.0 (livello appena iniziato)', () {
      // A 77 XP si è al livello 2 con 0 progresso verso il 3
      final progress = XpService.levelProgress(77);
      expect(progress, closeTo(0.0, 0.001));
    });

    test('progresso sempre in [0.0, 1.0]', () {
      for (final xp in [0, 77, 100, 306, 1000, 50000, 750000]) {
        final p = XpService.levelProgress(xp);
        expect(p, greaterThanOrEqualTo(0.0), reason: 'xp=$xp');
        expect(p, lessThanOrEqualTo(1.0), reason: 'xp=$xp');
      }
    });

    test('al livello massimo (750000 XP) → 1.0', () {
      expect(XpService.levelProgress(750000), 1.0);
    });
  });

  group('XpService - xpToNextLevel', () {
    test('0 XP → 77 per raggiungere liv.2', () {
      expect(XpService.xpToNextLevel(0), 77);
    });

    test('76 XP → 1 per raggiungere liv.2', () {
      expect(XpService.xpToNextLevel(76), 1);
    });

    test('77 XP (liv.2) → 229 per raggiungere liv.3 (306-77)', () {
      expect(XpService.xpToNextLevel(77), 229);
    });

    test('al livello massimo → 0', () {
      expect(XpService.xpToNextLevel(750000), 0);
    });

    test('xpToNextLevel non è mai negativo', () {
      for (final xp in [0, 50, 77, 306, 100000, 750000]) {
        expect(XpService.xpToNextLevel(xp), greaterThanOrEqualTo(0));
      }
    });
  });

  group('XpService - xpForRarity', () {
    test('Ghost Rare → 40', () => expect(XpService.xpForRarity('Ghost Rare'), 40));
    test('Prismatic Secret Rare → 40', () {
      expect(XpService.xpForRarity('Prismatic Secret Rare'), 40);
    });
    test('Secret Rare → 30', () => expect(XpService.xpForRarity('Secret Rare'), 30));
    test('Ultimate Rare → 30', () => expect(XpService.xpForRarity('Ultimate Rare'), 30));
    test('Ultra Rare → 25', () => expect(XpService.xpForRarity('Ultra Rare'), 25));
    test('Super Rare → 20', () => expect(XpService.xpForRarity('Super Rare'), 20));
    test('Rare → 10', () => expect(XpService.xpForRarity('Rare'), 10));
    test('Rare Holo → 10 (contiene "rare")', () {
      expect(XpService.xpForRarity('Rare Holo'), 10);
    });
    test('Common → 5 (default)', () => expect(XpService.xpForRarity('Common'), 5));
    test('stringa vuota → 5 (default)', () => expect(XpService.xpForRarity(''), 5));
    test('case insensitive: "ultra rare" → 25', () {
      expect(XpService.xpForRarity('ultra rare'), 25);
    });
    test('case insensitive: "GHOST RARE" → 40', () {
      expect(XpService.xpForRarity('GHOST RARE'), 40);
    });
    // Priorità: ghost viene prima di rare
    test('"ghost" ha priorità su "rare"', () {
      expect(XpService.xpForRarity('Ghost Rare'), 40);
    });
  });

  group('AvatarDef - isUnlocked', () {
    test('avatar livello: sbloccato se livello >= unlockLevel', () {
      const avatar = AvatarDef(
        id: 'test_1',
        name: 'Test',
        unlockType: AvatarUnlockType.level,
        unlockLevel: 10,
        icon: Icons.star,
        background: Color(0xFF000000),
        iconColor: Color(0xFFFFFFFF),
      );
      expect(avatar.isUnlocked(9, {}), isFalse);
      expect(avatar.isUnlocked(10, {}), isTrue);
      expect(avatar.isUnlocked(11, {}), isTrue);
    });

    test('avatar collezione: sbloccato se completamento >= unlockPercent', () {
      const avatar = AvatarDef(
        id: 'test_2',
        name: 'Test',
        unlockType: AvatarUnlockType.collection,
        collectionKey: 'yugioh',
        unlockPercent: 50,
        icon: Icons.star,
        background: Color(0xFF000000),
        iconColor: Color(0xFFFFFFFF),
      );
      // 49% → non sbloccato
      expect(avatar.isUnlocked(1, {'yugioh': 0.49}), isFalse);
      // 50% → sbloccato
      expect(avatar.isUnlocked(1, {'yugioh': 0.50}), isTrue);
      // 100% → sbloccato
      expect(avatar.isUnlocked(1, {'yugioh': 1.0}), isTrue);
    });

    test('avatar collezione: chiave assente → 0% → non sbloccato', () {
      const avatar = AvatarDef(
        id: 'test_3',
        name: 'Test',
        unlockType: AvatarUnlockType.collection,
        collectionKey: 'pokemon',
        unlockPercent: 10,
        icon: Icons.star,
        background: Color(0xFF000000),
        iconColor: Color(0xFFFFFFFF),
      );
      expect(avatar.isUnlocked(99, {}), isFalse);
    });
  });

  group('XpService - unlockedAvatars', () {
    test('livello 1 senza completamenti → pochissimi avatar sbloccati', () {
      final unlocked = XpService.unlockedAvatars(1, {});
      // nessun avatar di livello (minimo è 10) e nessuna collezione completata
      expect(unlocked, isEmpty);
    });

    test('livello 100 → tutti gli avatar di livello sbloccati', () {
      final unlocked = XpService.unlockedAvatars(100, {});
      final levelAvatars = XpService.avatars
          .where((a) => a.unlockType == AvatarUnlockType.level)
          .toList();
      for (final avatar in levelAvatars) {
        expect(unlocked, contains(avatar),
            reason: '${avatar.id} dovrebbe essere sbloccato a livello 100');
      }
    });

    test('100% completamento yugioh → tutti i 20 avatar yugioh sbloccati', () {
      final unlocked = XpService.unlockedAvatars(1, {'yugioh': 1.0});
      final ygoAvatars = unlocked.where((a) => a.collectionKey == 'yugioh').toList();
      expect(ygoAvatars.length, 20);
    });

    test('0% completamento → nessun avatar collezione sbloccato', () {
      final unlocked = XpService.unlockedAvatars(1, {'yugioh': 0.0, 'pokemon': 0.0});
      final collectionAvatars = unlocked
          .where((a) => a.unlockType == AvatarUnlockType.collection)
          .toList();
      expect(collectionAvatars, isEmpty);
    });
  });

  group('XpService - levelThresholds integrità', () {
    test('primo threshold è 0 (livello 1 inizia da 0 XP)', () {
      expect(XpService.levelThresholds[0], 0);
    });

    test('100 soglie (livelli 1-100)', () {
      expect(XpService.levelThresholds.length, 100);
    });

    test('ultimo threshold è 750000', () {
      expect(XpService.levelThresholds.last, 750000);
    });

    test('le soglie sono strettamente crescenti', () {
      for (int i = 1; i < XpService.levelThresholds.length; i++) {
        expect(
          XpService.levelThresholds[i],
          greaterThan(XpService.levelThresholds[i - 1]),
          reason: 'threshold[$i] deve essere > threshold[${i - 1}]',
        );
      }
    });
  });

  group('XpService - avatars integrità', () {
    test('410 avatar totali', () {
      expect(XpService.avatars.length, 410);
    });

    test('nessun id duplicato', () {
      final ids = XpService.avatars.map((a) => a.id).toList();
      final unique = ids.toSet();
      expect(unique.length, ids.length, reason: 'ID avatar duplicati trovati!');
    });

    test('ogni avatar ha id e name non vuoti', () {
      for (final avatar in XpService.avatars) {
        expect(avatar.id, isNotEmpty, reason: 'Avatar con id vuoto trovato');
        expect(avatar.name, isNotEmpty, reason: 'Avatar ${avatar.id} ha name vuoto');
      }
    });

    test('avatar di tipo level hanno unlockLevel != null', () {
      for (final a in XpService.avatars.where((a) => a.unlockType == AvatarUnlockType.level)) {
        expect(a.unlockLevel, isNotNull, reason: '${a.id} manca unlockLevel');
      }
    });

    test('avatar di tipo collection hanno collectionKey e unlockPercent != null', () {
      for (final a in XpService.avatars.where((a) => a.unlockType == AvatarUnlockType.collection)) {
        expect(a.collectionKey, isNotNull, reason: '${a.id} manca collectionKey');
        expect(a.unlockPercent, isNotNull, reason: '${a.id} manca unlockPercent');
        expect(a.unlockPercent!, greaterThan(0));
        expect(a.unlockPercent!, lessThanOrEqualTo(100));
      }
    });

    test('10 avatar globali (di livello)', () {
      final global = XpService.avatars.where((a) => a.unlockType == AvatarUnlockType.level).toList();
      expect(global.length, 10);
    });

    test('400 avatar di collezione', () {
      final coll = XpService.avatars.where((a) => a.unlockType == AvatarUnlockType.collection).toList();
      expect(coll.length, 400);
    });

    test('20 collezioni con 20 avatar ciascuna', () {
      expect(XpService.collections.length, 20);
      for (final col in XpService.collections) {
        final count = XpService.avatars
            .where((a) => a.collectionKey == col.key)
            .length;
        expect(count, 20, reason: 'Collezione ${col.key} ha $count avatar invece di 20');
      }
    });
  });
}
