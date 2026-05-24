// lib/features/legal/privacy_policy_screen.dart
import 'package:flutter/material.dart';
import 'package:terraton_fan_app/features/legal/legal_screen.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _sections = [
    LegalSection(
      'What data we collect',
      'When AI Training is enabled in Settings, the app collects anonymous fan usage '
      'patterns: speed settings, operating modes (Normal, Boost, Nature, etc.), session '
      'duration, energy consumption in kWh, and which hours of the day the fan runs.\n\n'
      'We also attach weather context (daily temperature and humidity for central Kerala) '
      'and your estimated KSEB tariff slab, which the app calculates from total kWh usage.',
    ),
    LegalSection(
      'What we do NOT collect',
      '• Your name, email address, or any contact information\n'
      '• Your real device ID, IMEI, or phone number\n'
      '• Precise GPS location (weather uses a fixed Kerala coordinate, not your location)\n'
      '• Photos, microphone, or any data outside the Terraton app\n'
      '• Any data when AI Training is switched off',
    ),
    LegalSection(
      'How we anonymise data',
      'Your device is identified by the first 16 characters of a SHA-256 hash of a '
      'random installation identifier. This one-way hash cannot be reversed — there is '
      'no way to trace a record back to you or your phone.',
    ),
    LegalSection(
      'Where data is stored',
      'Anonymised records are sent over HTTPS to a Cloudflare Worker and stored in '
      'Cloudflare R2 object storage. We do not share this data with third parties or '
      'advertisers, and we do not sell it.',
    ),
    LegalSection(
      'How data is used',
      'Records are used exclusively to train the Terraton energy-optimisation AI model. '
      'A future app update will use this model to give personalised suggestions — for '
      'example, "switching to Speed 3 after midnight could save you ₹40 per month".',
    ),
    LegalSection(
      'Upload schedule',
      'Data is uploaded at most once per day, only when your phone is connected to '
      'Wi-Fi, and only for days that have already ended. Nothing is sent over mobile '
      'data. The app never uploads data for the current day.',
    ),
    LegalSection(
      'Your choices',
      'You can turn off data collection at any time in Settings → AI Training. Once '
      'off, no further data is sent. Existing records cannot be deleted on request '
      'because they carry no personally identifiable information — we have no way to '
      'match a record to a specific user.',
    ),
    LegalSection(
      'Data retention',
      'Usage records are kept in Cloudflare R2 for up to 12 months. After the next '
      'major model training cycle, older raw records are deleted and replaced by the '
      'trained model weights.',
    ),
    LegalSection(
      'Children',
      'This app is not directed at children under 13. We do not knowingly collect '
      'data from minors.',
    ),
    LegalSection(
      'Changes to this policy',
      'If we make material changes, the updated policy will be shown in the app on '
      'your next launch.',
    ),
    LegalSection(
      'Contact',
      'Questions about privacy? Email us at bleappterraton@gmail.com and we will '
      'respond within 5 business days.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return const LegalScreen(
      title: 'Privacy Policy',
      lastUpdated: 'May 2026',
      sections: _sections,
    );
  }
}
