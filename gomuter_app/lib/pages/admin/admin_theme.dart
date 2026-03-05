import 'package:flutter/material.dart';

// ── Orange / White Admin Theme ──────────────────────────────────────────
const Color adminPrimary = Color(0xFFF97316); // vibrant orange
const Color adminPrimaryLight = Color(0xFFFB923C); // lighter orange
const Color adminAccent = Color(0xFFFDBA74); // soft peach
const Color adminBg = Color(0xFFFFF7ED); // warm off-white
const Color adminCardBg = Colors.white;
const Color adminDarkText = Color(0xFF1A1A2E);
const Color adminSubText = Color(0xFF6B7280); // grey-500
const Color adminBorder = Color(0xFFE5E7EB); // grey-200

// Gradient used for highlighted cards / buttons
const LinearGradient adminGradient = LinearGradient(
  colors: [Color(0xFFF97316), Color(0xFFFB923C)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// Status colors (unchanged from original – these are semantic)
const Color statusPending = Color(0xFFF97316);
const Color statusAccepted = Color(0xFF22C55E);
const Color statusRejected = Color(0xFFEF4444);
