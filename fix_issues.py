import os
import re

def replace_in_file(filepath, search_str, replace_str):
    with open(filepath, 'r') as f:
        content = f.read()
    content = content.replace(search_str, replace_str)
    with open(filepath, 'w') as f:
        f.write(content)

def replace_regex_in_file(filepath, pattern, replace_str):
    with open(filepath, 'r') as f:
        content = f.read()
    content = re.sub(pattern, replace_str, content)
    with open(filepath, 'w') as f:
        f.write(content)

# Fix print statements (add debugPrint import if necessary)
files_with_print = [
    'lib/screens/employee/employee_home_screen.dart',
    'lib/services/email_service.dart',
    'lib/services/leave_service.dart',
    'lib/services/payroll_service.dart',
    'lib/services/staff_service.dart',
    'lib/utils/firestore_seeds.dart',
]

for file in files_with_print:
    replace_regex_in_file(file, r'\bprint\(', 'debugPrint(')
    # Add import if missing
    with open(file, 'r') as f:
        content = f.read()
    if 'debugPrint' in content and 'import \'package:flutter/foundation.dart\';' not in content:
        content = 'import \'package:flutter/foundation.dart\';\n' + content
        with open(file, 'w') as f:
            f.write(content)

# Fix manager_dashboard_screen.dart: dead_null_aware_expression and unused elements/fields
manager_file = 'lib/screens/manager/manager_dashboard_screen.dart'
# unused fields
replace_regex_in_file(manager_file, r'final int page\s*=\s*0;\n', '')
replace_regex_in_file(manager_file, r'int present\s*=\s*0;\n', '')
replace_regex_in_file(manager_file, r'int late\s*=\s*0;\n', '')
replace_regex_in_file(manager_file, r'int absent\s*=\s*0;\n', '')
replace_regex_in_file(manager_file, r'final int governmentHoliday\s*=\s*0;\n', '')
replace_regex_in_file(manager_file, r'final int hinduHoliday\s*=\s*0;\n', '')
replace_regex_in_file(manager_file, r'final int muslimHoliday\s*=\s*0;\n', '')
replace_regex_in_file(manager_file, r'final int christianHoliday\s*=\s*0;\n', '')
# avoid_types_as_parameter_names
replace_regex_in_file(manager_file, r'\(double sum,', '(double totalSum,')
# dead_null_aware_expression line 3184:51. We need to see the line first, but maybe it is something like `??` or `?.`. We can fix it manually.
