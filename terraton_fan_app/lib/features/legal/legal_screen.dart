// lib/features/legal/legal_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:terraton_fan_app/shared/theme.dart';

/// Reusable scrollable screen for Privacy Policy and Terms of Service.
class LegalScreen extends StatelessWidget {
  final String title;
  final String lastUpdated;
  final List<LegalSection> sections;

  const LegalScreen({
    super.key,
    required this.title,
    required this.lastUpdated,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: kText, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: GoogleFonts.manrope(
            fontSize: 17, fontWeight: FontWeight.w700, color: kText,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 80),
        children: [
          Text(
            'Last updated: $lastUpdated',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10, color: kTextDim, letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 20),
          ...sections.map((s) => _SectionCard(section: s)),
        ],
      ),
    );
  }
}

class LegalSection {
  final String heading;
  final String body;
  const LegalSection(this.heading, this.body);
}

class _SectionCard extends StatelessWidget {
  final LegalSection section;
  const _SectionCard({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.heading,
            style: GoogleFonts.manrope(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: kYellow, letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            section.body,
            style: GoogleFonts.manrope(
              fontSize: 13, color: kTextMut, height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
