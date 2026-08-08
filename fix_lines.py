import re

def comment_out(lines, start_pattern, end_brace_count=0):
    start_idx = -1
    for i, line in enumerate(lines):
        if re.search(start_pattern, line):
            start_idx = i
            break
    if start_idx == -1: return lines

    # comment out until balanced braces
    brace_count = end_brace_count
    for i in range(start_idx, len(lines)):
        line = lines[i]
        brace_count += line.count('{')
        brace_count -= line.count('}')
        lines[i] = '// ' + lines[i]
        if brace_count == 0:
            break
    return lines

path_emp = 'lib/screens/employee/employee_home_screen.dart'
with open(path_emp, 'r') as f: lines_emp = f.readlines()

# employee_home_screen unused elements
lines_emp = comment_out(lines_emp, r'Widget _initial\(')
lines_emp = comment_out(lines_emp, r'class _OverviewTopInfo')
lines_emp = comment_out(lines_emp, r'class _OverviewProfileChip')
lines_emp = comment_out(lines_emp, r'class _MonthlyAttendanceSummary')
lines_emp = comment_out(lines_emp, r'class _ScanningRulesPanel')
# staff colors
for color in ['_staffGreen3', '_staffGreen4', '_staffRed2', '_staffAmber4', '_staffViolet', '_staffTintViolet', '_staffTintGreen', '_staffTintGreen2', '_staffTintAmber', '_staffTintAmber3', '_staffTintRed']:
    for i, line in enumerate(lines_emp):
        if color in line and 'const Color' in line:
            lines_emp[i] = '// ' + line

# _HomeMetric, _ScanningRuleRow
lines_emp = comment_out(lines_emp, r'class _HomeMetric')
lines_emp = comment_out(lines_emp, r'class _ScanningRuleRow')


with open(path_emp, 'w') as f: f.writelines(lines_emp)


path_mgr = 'lib/screens/manager/manager_dashboard_screen.dart'
with open(path_mgr, 'r') as f: lines_mgr = f.readlines()

# manager fields
for field in ['page =', 'present =', 'late =', 'absent =', 'governmentHoliday =', 'hinduHoliday =', 'muslimHoliday =', 'christianHoliday =']:
    for i, line in enumerate(lines_mgr):
        if field in line and 'static const Color' in line:
            lines_mgr[i] = '// ' + line

lines_mgr = comment_out(lines_mgr, r'Widget _buildOwnPermissionPage\(')
lines_mgr = comment_out(lines_mgr, r'Widget _buildExportButton\(')
lines_mgr = comment_out(lines_mgr, r'void _exportAttendance\(')
lines_mgr = comment_out(lines_mgr, r'const Color _mgrIndigo')

# we need to comment out lines 6370 and 6614
def comment_out_at_line(lines, line_num):
    start = line_num - 1
    brace_count = 0
    for i in range(start, len(lines)):
        brace_count += lines[i].count('{')
        brace_count -= lines[i].count('}')
        lines[i] = '// ' + lines[i]
        if brace_count == 0:
            break

# comment_out_at_line(lines_mgr, 6370)
# comment_out_at_line(lines_mgr, 6379)
# comment_out_at_line(lines_mgr, 6614)
# comment_out_at_line(lines_mgr, 6623)

with open(path_mgr, 'w') as f: f.writelines(lines_mgr)

