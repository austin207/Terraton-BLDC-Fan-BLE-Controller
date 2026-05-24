// lib/features/legal/terms_screen.dart
import 'package:flutter/material.dart';
import 'package:terraton_fan_app/features/legal/legal_screen.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const _sections = [
    LegalSection(
      'Acceptance',
      'By installing or using the Terraton Fan Controller app ("the App"), you agree '
      'to these Terms of Service. If you do not agree, please uninstall the App.',
    ),
    LegalSection(
      'What the App does',
      'The App connects to Terraton BLDC ceiling fans over Bluetooth Low Energy (BLE) '
      'to let you control fan speed, operating mode, timer, and lighting. It also '
      'displays energy usage analytics and optional AI-powered efficiency suggestions.',
    ),
    LegalSection(
      'Authorised use',
      'You may only use the App to control fans that you own or that you have explicit '
      'permission to operate. Using the App to access or control a fan without the '
      'owner\'s consent is prohibited and may violate applicable law.',
    ),
    LegalSection(
      'No warranty',
      'The App is provided "as is" without warranties of any kind. BLE connectivity '
      'depends on your phone\'s hardware, Android version, and physical proximity to '
      'the fan. We do not guarantee uninterrupted, error-free operation.',
    ),
    LegalSection(
      'Limitation of liability',
      'To the maximum extent permitted by law, Terraton and its developers are not '
      'liable for any direct, indirect, or incidental damages arising from your use '
      'of — or inability to use — the App, including damage to any connected equipment.',
    ),
    LegalSection(
      'Data and privacy',
      'Our Privacy Policy (also accessible from Settings) describes what data we '
      'collect, how it is anonymised, and how you can opt out. By using the App you '
      'acknowledge and agree to our data practices.',
    ),
    LegalSection(
      'Updates',
      'We may update the App or these Terms at any time. Continued use of the App '
      'after an update constitutes your acceptance of the revised Terms.',
    ),
    LegalSection(
      'Governing law',
      'These Terms are governed by the laws of Kerala, India. Any disputes will be '
      'subject to the exclusive jurisdiction of the courts of Kerala.',
    ),
    LegalSection(
      'Contact',
      'For any questions regarding these Terms, contact us at bleappterraton@gmail.com.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return const LegalScreen(
      title: 'Terms of Service',
      lastUpdated: 'May 2026',
      sections: _sections,
    );
  }
}
