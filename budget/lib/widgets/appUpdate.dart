// Локальная версия: проверка обновлений через GitHub Releases.
//
// Каждая сборка в GitHub Actions получает номер запуска N и собирается
// с build-number = 1000 + N, а релиз называется тегом build-N.
// Приложение сравнивает свой номер с последним релизом и предлагает скачать APK.

import 'dart:convert';
import 'dart:io';

import 'package:budget/functions.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const String updateRepo = "polina-courses/cashew";
const int buildNumberOffset = 1000;

class AppRelease {
  AppRelease({
    required this.build,
    required this.name,
    required this.notes,
    required this.apkUrl,
    required this.pageUrl,
  });
  final int build;
  final String name;
  final String notes;
  final String? apkUrl;
  final String pageUrl;
}

/// Номер текущей сборки (N из build-N). 0 — если собрано не через GitHub Actions.
int currentAppBuild() {
  int raw = int.tryParse(packageInfoGlobal?.buildNumber ?? "") ?? 0;
  int build = raw - buildNumberOffset;
  return build > 0 ? build : 0;
}

Future<AppRelease> fetchLatestRelease() async {
  HttpClient client = HttpClient()..connectionTimeout = Duration(seconds: 10);
  try {
    HttpClientRequest request = await client.getUrl(
        Uri.parse("https://api.github.com/repos/$updateRepo/releases/latest"));
    request.headers.set(HttpHeaders.acceptHeader, "application/vnd.github+json");
    request.headers.set(HttpHeaders.userAgentHeader, "cashew-local");
    HttpClientResponse response =
        await request.close().timeout(Duration(seconds: 15));
    String body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw "HTTP ${response.statusCode}";
    }
    Map<String, dynamic> json = jsonDecode(body);
    String tag = (json["tag_name"] ?? "").toString();
    int build = int.tryParse(tag.replaceAll(RegExp(r"[^0-9]"), "")) ?? 0;
    String? apkUrl;
    for (dynamic asset in (json["assets"] ?? [])) {
      String name = (asset["name"] ?? "").toString();
      if (name.endsWith(".apk")) {
        apkUrl = asset["browser_download_url"];
        break;
      }
    }
    return AppRelease(
      build: build,
      name: (json["name"] ?? tag).toString(),
      notes: (json["body"] ?? "").toString().trim(),
      apkUrl: apkUrl,
      pageUrl: (json["html_url"] ??
              "https://github.com/$updateRepo/releases/latest")
          .toString(),
    );
  } finally {
    client.close();
  }
}

/// Прямой адрес файла после перенаправления GitHub (release-assets.githubusercontent.com).
/// Ссылки github.com на телефоне может перехватить приложение GitHub, и его загрузчик
/// зависает; конечный адрес файла открывается обычным браузером.
Future<String?> resolveDownloadUrl(String url) async {
  HttpClient client = HttpClient()..connectionTimeout = Duration(seconds: 10);
  try {
    HttpClientRequest request = await client.getUrl(Uri.parse(url));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.userAgentHeader, "cashew-local");
    HttpClientResponse response =
        await request.close().timeout(Duration(seconds: 15));
    String? location = response.headers.value(HttpHeaders.locationHeader);
    await response.drain();
    if (response.isRedirect && location != null && location.isNotEmpty) {
      return location;
    }
    return null;
  } catch (e) {
    print("Could not resolve download url " + e.toString());
    return null;
  } finally {
    client.close(force: true);
  }
}

class AppUpdateSettingsTile extends StatefulWidget {
  const AppUpdateSettingsTile({super.key});

  @override
  State<AppUpdateSettingsTile> createState() => _AppUpdateSettingsTileState();
}

// Результат проверки живёт до перезапуска приложения, чтобы не дёргать GitHub
// при каждом открытии настроек. Тап по плашке проверяет заново.
Future<AppRelease>? _cachedCheck;

class _AppUpdateSettingsTileState extends State<AppUpdateSettingsTile> {
  late Future<AppRelease> check = _cachedCheck ??= fetchLatestRelease();

  void recheck() {
    setState(() {
      _cachedCheck = fetchLatestRelease();
      check = _cachedCheck!;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return SizedBox.shrink();
    int current = currentAppBuild();
    String currentLabel = current > 0 ? "сборка $current" : "локальная сборка";

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: FutureBuilder<AppRelease>(
        future: check,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return SettingsContainer(
              title: "Проверяю обновления…",
              description: "Установлена $currentLabel",
              icon: Icons.sync_rounded,
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return SettingsContainer(
              title: "Не удалось проверить обновления",
              description:
                  "Установлена $currentLabel. Нажмите, чтобы повторить",
              icon: Icons.cloud_off_rounded,
              onTap: recheck,
            );
          }
          AppRelease release = snapshot.data!;
          bool hasUpdate = release.build > current;
          if (!hasUpdate) {
            return SettingsContainer(
              title: "Установлена последняя версия",
              description: "$currentLabel. Нажмите, чтобы проверить ещё раз",
              icon: Icons.check_circle_outline_rounded,
              onTap: recheck,
            );
          }
          String notes = release.notes.split("\n").first.trim();
          return SettingsContainer(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            title: "Доступна ${release.name.toLowerCase()}",
            description: "Сейчас: $currentLabel" +
                (notes.isNotEmpty ? "\nЧто нового: $notes" : "") +
                "\nНажмите, чтобы скачать",
            icon: Icons.system_update_rounded,
            onTap: () async {
              String? direct = release.apkUrl == null
                  ? null
                  : await resolveDownloadUrl(release.apkUrl!);
              bool opened =
                  await openUrl(direct ?? release.apkUrl ?? release.pageUrl);
              if (!opened) await openUrl(release.pageUrl);
            },
          );
        },
      ),
    );
  }
}
