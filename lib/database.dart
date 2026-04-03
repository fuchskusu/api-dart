import 'dart:convert';
import 'dart:io';

import 'package:api_fussball_dart/entities/font.dart';
import 'package:api_fussball_dart/entities/rate_limit.dart';
import 'package:api_fussball_dart/entities/user.dart';
import 'package:isar/isar.dart';

class Database {
  static Isar? _isarInstance;

  static Future get isarInstance async {
    if (_isarInstance == null) {
      final String dataDirectory =
          Platform.environment['DATA_DIR'] ?? Directory.current.path;

      await Isar.initializeIsarCore(download: true);
      _isarInstance = await Isar.open(
        [UserSchema, FontSchema, RateLimitSchema],
        directory: dataDirectory,
      );
    }

    return _isarInstance!;
  }
}

class FontManager {
  Future<Map?> findByName(String name) async {
    final isar = await Database.isarInstance;
    Font? font = await isar.fonts.where().filter().nameEqualTo(name).findFirst();

    if (font == null) {
      return null;
    }

    return Map<String, dynamic>.from(json.decode(font.info!));
  }

  Future save(String name, Map info) async {
    final isar = await Database.isarInstance;

    final newFont = Font()
      ..name = name
      ..info = json.encode(info);

    await isar.writeTxn(() async {
      await isar.fonts.put(newFont);
    });
  }

  Future<List<int>> deleteAll() async {
    final isar = await Database.isarInstance;
    final allFonts = await isar.fonts.where().findAll();
    final ids = allFonts.map((e) => e.id).toList();

    await isar.writeTxn(() async {
      await isar.fonts.clear();
    });

    return ids;
  }
}

class RateLimitManager {
  Future<int> get(int userId) async {
    final isar = await Database.isarInstance;

    return await isar.rateLimits
        .where()
        .filter()
        .userIdEqualTo(userId)
        .timeEqualTo(_getDate())
        .count();
  }

  Future add(int userId) async {
    final isar = await Database.isarInstance;

    final newRateLimit = RateLimit()
      ..userId = userId
      ..time = _getDate();

    await isar.writeTxn(() async {
      await isar.rateLimits.put(newRateLimit);
    });
  }

  Future clear() async {
    final isar = await Database.isarInstance;

    await isar.writeTxn(() async {
      await isar.rateLimits.clear();
    });
  }

  int _getDate() {
    final now = DateTime.now();
    final formattedDate =
        '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';

    return int.parse(formattedDate);
  }
}

Future<List<User?>> findAllUser() async {
  final isar = await Database.isarInstance;
  return await isar.users.where().findAll();
}

Future<User?> findUserByToken(String token) async {
  final isar = await Database.isarInstance;
  return await isar.users.where().filter().tokenEqualTo(token).findFirst();
}

Future saveUser(String email, String token) async {
  final isar = await Database.isarInstance;
  final userDb = isar.users;

  await isar.writeTxn(() async {
    await userDb.where().filter().emailEqualTo(email).deleteAll();
  });

  final newUser = User()
    ..email = email
    ..token = token;

  await isar.writeTxn(() async {
    await userDb.put(newUser);
  });
}

Future deleteUserByEmail(String email) async {
  final isar = await Database.isarInstance;

  await isar.writeTxn(() async {
    await isar.users.where().filter().emailEqualTo(email).deleteAll();
  });
}

Future saveUsersToJson() async {
  final users = await findAllUser();
  final Map<String, String> userMap = {};

  for (var user in users) {
    if (user?.email != null && user?.token != null) {
      userMap[user!.email!] = user.token!;
    }
  }

  final jsonStr = jsonEncode(userMap);
  await File('users.json').writeAsString(jsonStr);
}

Future<List<String>> importUsersFromJson() async {
  final file = File('users.json');

  if (!await file.exists()) {
    throw Exception('File users.json does not exist');
  }

  final content = await file.readAsString();
  final Map<String, dynamic> usersMap = jsonDecode(content);
  final List<String> importedEmails = [];

  for (final email in usersMap.keys) {
    await saveUser(email, usersMap[email].toString());
    importedEmails.add(email);
  }

  return importedEmails;
}