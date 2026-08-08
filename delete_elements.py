import os
import re

def delete_class(file_path, class_name):
    with open(file_path, 'r') as f:
        content = f.read()
    
    # We match "class ClassName ... {" up to the matching closing brace.
    # We can do this safely by counting braces.
    pattern = r'(class\s+' + class_name + r'\b.*?\{)'
    match = re.search(pattern, content, re.DOTALL)
    if not match:
        # Check if it's a method
        pattern = r'(\w+\s+' + class_name + r'\(.*?\)\s*\{)'
        match = re.search(pattern, content, re.DOTALL)
        if not match:
            # Check if it's a widget method
            pattern = r'(Widget\s+' + class_name + r'\(.*?\)\s*\{)'
            match = re.search(pattern, content, re.DOTALL)
            if not match:
                print(f"Could not find {class_name}")
                return

    start_idx = match.start()
    
    # Now find the matching closing brace
    brace_count = 0
    in_string = False
    in_char = False
    escape = False
    end_idx = -1
    
    for i in range(match.end() - 1, len(content)):
        c = content[i]
        if escape:
            escape = False
            continue
        if c == '\\':
            escape = True
            continue
        if c == '"' and not in_char:
            in_string = not in_string
        elif c == "'" and not in_string:
            in_char = not in_char
            
        if not in_string and not in_char:
            if c == '{':
                brace_count += 1
            elif c == '}':
                brace_count -= 1
                if brace_count == 0:
                    end_idx = i
                    break
                    
    if end_idx != -1:
        new_content = content[:start_idx] + content[end_idx+1:]
        with open(file_path, 'w') as f:
            f.write(new_content)
        print(f"Deleted {class_name} in {file_path}")
    else:
        print(f"Could not find closing brace for {class_name}")

employee_elements = ['_initial', '_OverviewTopInfo', '_OverviewProfileChip', '_MonthlyAttendanceSummary', '_ScanningRulesPanel']
for el in employee_elements:
    delete_class('lib/screens/employee/employee_home_screen.dart', el)

manager_elements = ['_buildOwnPermissionPage', '_buildExportButton', '_initials', '_avatarColor']
for el in manager_elements:
    delete_class('lib/screens/manager/manager_dashboard_screen.dart', el)
    # They appear twice, delete again if exists
    delete_class('lib/screens/manager/manager_dashboard_screen.dart', el)
    delete_class('lib/screens/manager/manager_dashboard_screen.dart', el)

