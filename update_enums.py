import os
import re

def process_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # Enum Definitions
    if 'attendance_log.dart' in filepath:
        content = re.sub(
            r'enum AttendanceEventType \{\s*CHECK_IN,\s*TEMP_EXIT,\s*RE_ENTRY,\s*FINAL_CHECKOUT,\s*UNAUTHORIZED_EXIT\s*\}',
            r"enum AttendanceEventType {\n  checkIn('CHECK_IN'),\n  tempExit('TEMP_EXIT'),\n  reEntry('RE_ENTRY'),\n  finalCheckout('FINAL_CHECKOUT'),\n  unauthorizedExit('UNAUTHORIZED_EXIT');\n\n  final String firestoreValue;\n  const AttendanceEventType(this.firestoreValue);\n}",
            content
        )
        content = content.replace("e.name == data['eventType']", "e.firestoreValue == data['eventType']")
        content = content.replace("'eventType': eventType.name", "'eventType': eventType.firestoreValue")
        content = content.replace("orElse: () => AttendanceEventType.CHECK_IN", "orElse: () => AttendanceEventType.checkIn")

    if 'attendance_model.dart' in filepath:
        content = re.sub(
            r'enum AttendanceState \{\s*NONE,\s*CHECK_IN,\s*TEMP_EXIT,\s*RE_ENTRY,\s*FINAL_CHECKOUT,\s*UNAUTHORIZED_EXIT\s*\}',
            r"enum AttendanceState {\n  none('NONE'),\n  checkIn('CHECK_IN'),\n  tempExit('TEMP_EXIT'),\n  reEntry('RE_ENTRY'),\n  finalCheckout('FINAL_CHECKOUT'),\n  unauthorizedExit('UNAUTHORIZED_EXIT');\n\n  final String firestoreValue;\n  const AttendanceState(this.firestoreValue);\n}",
            content
        )
        content = content.replace("e.name == s", "e.firestoreValue == s")
        content = content.replace("'currentState': currentState.name", "'currentState': currentState.firestoreValue")
        content = content.replace("orElse: () => AttendanceState.NONE", "orElse: () => AttendanceState.none")
        content = content.replace("this.currentState = AttendanceState.NONE", "this.currentState = AttendanceState.none")
        content = content.replace("_state(d['currentState'] ?? 'NONE')", "_state(d['currentState'] ?? 'NONE')") # string literal doesn't change

    # Global usages
    content = content.replace('.CHECK_IN', '.checkIn')
    content = content.replace('.TEMP_EXIT', '.tempExit')
    content = content.replace('.RE_ENTRY', '.reEntry')
    content = content.replace('.FINAL_CHECKOUT', '.finalCheckout')
    content = content.replace('.UNAUTHORIZED_EXIT', '.unauthorizedExit')
    content = content.replace('.NONE', '.none')

    with open(filepath, 'w') as f:
        f.write(content)

def main():
    for root, dirs, files in os.walk('lib'):
        for file in files:
            if file.endswith('.dart'):
                filepath = os.path.join(root, file)
                process_file(filepath)

if __name__ == '__main__':
    main()
