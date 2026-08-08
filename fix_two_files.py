import re

def fix_employee_home():
    path = 'lib/screens/employee/employee_home_screen.dart'
    with open(path, 'r') as f:
        content = f.read()
    content = content.replace('print(', 'debugPrint(')
    content = re.sub(r'import \'package:flutter/material\.dart\';', r"import 'package:flutter/material.dart';\nimport 'package:intl/intl.dart';\nimport 'package:cloud_firestore/cloud_firestore.dart';", content, count=1)
    with open(path, 'w') as f:
        f.write(content)

def fix_manager_dashboard():
    path = 'lib/screens/manager/manager_dashboard_screen.dart'
    with open(path, 'r') as f:
        content = f.read()
    
    # avoid_types_as_parameter_names
    content = content.replace('(sum, item) => sum + item.value', '(totalSum, item) => totalSum + item.value')
    # dead_null_aware_expression
    content = content.replace('req.reason ?? \'\'', 'req.reason')
    with open(path, 'w') as f:
        f.write(content)

fix_employee_home()
fix_manager_dashboard()
