path_mgr = 'lib/screens/manager/manager_dashboard_screen.dart'
with open(path_mgr, 'r') as f: lines_mgr = f.readlines()
for i, line in enumerate(lines_mgr):
    if 'package:csv/csv.dart' in line or 'package:file_saver/file_saver.dart' in line:
        lines_mgr[i] = '// ' + line
with open(path_mgr, 'w') as f: f.writelines(lines_mgr)
