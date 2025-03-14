# 勤怠管理アプリ

GPSジオフェンスで自動打刻できる勤怠管理アプリ（Flutter）。

オフィスに着いたら自動で出勤、出たら自動で退勤。
手動打刻もできるが、ジオフェンス範囲外からの打刻は弾く仕様。

## 技術構成

- Flutter + Riverpod + GoRouter
- Firebase Auth / Firestore
- Google Maps Flutter + Geolocator
- ジオフェンス: Android (Kotlin) / iOS (Swift) のネイティブ実装
- Flutter Local Notifications（リマインダー）
- CSV入出力

ジオフェンスはFlutterプラグインだと精度がいまいちだったので、
プラットフォームごとにネイティブで書いてMethodChannelで繋いでいる。

## 機能

- 打刻（出勤/退勤）+ ジオフェンス検証
- 自動打刻（ジオフェンスイベントで発火）
- 管理者ダッシュボード（従業員のリアルタイム出勤状況）
- 休暇申請 → 承認/却下ワークフロー
- チームチャット
- 月間サマリー + CSV出力
- 招待コードで会社に参加

## セットアップ

```bash
flutter pub get
flutterfire configure
flutter run
```

Google Maps APIキーは`android/app/src/main/AndroidManifest.xml`と
`ios/Runner/AppDelegate.swift`に設定する。
