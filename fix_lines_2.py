def comment_out_at_line(lines, line_num):
    start = line_num - 1
    if start >= len(lines) or start < 0: return
    brace_count = 0
    for i in range(start, len(lines)):
        brace_count += lines[i].count('{')
        brace_count -= lines[i].count('}')
        lines[i] = '// ' + lines[i]
        if brace_count == 0:
            break

def comment_single_line(lines, line_num):
    start = line_num - 1
    if start >= 0 and start < len(lines):
        lines[start] = '// ' + lines[start]

# Employee Home Screen
path_emp = 'lib/screens/employee/employee_home_screen.dart'
with open(path_emp, 'r') as f: lines_emp = f.readlines()
comment_single_line(lines_emp, 38) # page
comment_single_line(lines_emp, 81) # _monthWfh
comment_out_at_line(lines_emp, 1519) # _isSameDate
comment_out_at_line(lines_emp, 4137) # _initial
with open(path_emp, 'w') as f: f.writelines(lines_emp)

# Manager Dashboard Screen
path_mgr = 'lib/screens/manager/manager_dashboard_screen.dart'
with open(path_mgr, 'r') as f: lines_mgr = f.readlines()
comment_out_at_line(lines_mgr, 5798) # _exportAttendance
comment_out_at_line(lines_mgr, 6320) # _initials
comment_out_at_line(lines_mgr, 6329) # _avatarColor
comment_out_at_line(lines_mgr, 6564) # _initials
comment_out_at_line(lines_mgr, 6573) # _avatarColor
with open(path_mgr, 'w') as f: f.writelines(lines_mgr)
