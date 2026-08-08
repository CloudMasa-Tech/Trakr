/// Canonical list of departments used across onboarding, directory, filters,
/// and admin screens. Update this file to add/remove a department app-wide.
const List<String> kAppDepartments = <String>[
  'Cloud Engineer',
  'Marketing Executives',
  'Sales Executives',
  'HR',
  'Chief Executives',
];

String displayDepartment(String? value) {
  switch (value?.trim()) {
    case 'Cloud Computing':
    case 'Cloud Platform':
    case 'Cloud Engineering':
      return 'Cloud Engineer';
    case 'Marketing':
      return 'Marketing Executives';
    case 'Sales':
      return 'Sales Executives';
    default:
      return value?.trim() ?? '';
  }
}

bool isValidDepartment(String? value) {
  if (value == null) return false;
  return kAppDepartments.contains(displayDepartment(value));
}
