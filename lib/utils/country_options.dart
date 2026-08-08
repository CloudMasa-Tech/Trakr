const List<String> kNationalityOptions = [
  'Indian',
  'American',
  'Australian',
  'Bangladeshi',
  'British',
  'Canadian',
  'Chinese',
  'French',
  'German',
  'Indonesian',
  'Japanese',
  'Malaysian',
  'Nepalese',
  'Singaporean',
  'Sri Lankan',
  'Thai',
  'UAE',
  'Vietnamese',
];

const List<String> kPhoneDialCodeOptions = [
  '+91',
  '+1',
  '+44',
  '+61',
  '+65',
  '+971',
  '+60',
  '+94',
  '+880',
  '+977',
  '+81',
  '+86',
  '+49',
  '+33',
  '+66',
  '+84',
  '+62',
];

String splitDialCodeFromPhone(
  String raw, {
  String fallbackDialCode = '+91',
}) {
  final phone = raw.trim();
  for (final code in kPhoneDialCodeOptions) {
    if (phone.startsWith(code)) return code;
  }
  return fallbackDialCode;
}

String phoneWithoutDialCode(String raw) {
  final phone = raw.trim();
  for (final code in kPhoneDialCodeOptions) {
    if (phone.startsWith(code)) {
      return phone.substring(code.length).trim();
    }
  }
  return phone;
}
