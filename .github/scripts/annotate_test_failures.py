"""Report failing Flutter tests as GitHub Actions error annotations.

Reads the JSON report written by `flutter test --file-reporter json:<path>`
(see https://dart.dev/go/test-docs/json_reporter.md) and prints one `::error`
workflow command per failed test. GitHub then shows each failure on the
commit and pull request pages, so nobody has to open the job log to find it.
"""
import json
import os
import sys
from urllib.parse import unquote, urlparse

MAX_MESSAGE = 2000  # characters of each failure message to keep


def escape(value, is_property=False):
    """Escape a value for use in a workflow command."""
    value = value.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
    if is_property:
        value = value.replace(':', '%3A').replace(',', '%2C')
    return value


def repo_path(location, workspace):
    """Turn a file URL or path from the report into a repository path."""
    if not location:
        return None
    if location.startswith('file:'):
        location = unquote(urlparse(location).path)
    elif '://' in location:
        return None
    if os.path.isabs(location):
        try:
            location = os.path.relpath(location, workspace)
        except ValueError:  # On Windows, a path on another drive.
            return None
    location = location.replace(os.sep, '/')
    # Frames inside the Flutter SDK or the pub cache are not repository files.
    return None if location.startswith('../') else location


def main(report_path):
    workspace = os.environ.get('GITHUB_WORKSPACE', os.getcwd())
    suites, tests, errors, failed = {}, {}, {}, []
    try:
        report = open(report_path, encoding='utf-8')
    except OSError as error:
        print(f'::warning::No test report to annotate: {escape(str(error))}')
        return
    with report:
        for line in report:
            try:
                event = json.loads(line)
            except ValueError:
                continue
            kind = event.get('type')
            if kind == 'suite':
                suites[event['suite']['id']] = event['suite'].get('path')
            elif kind == 'testStart':
                tests[event['test']['id']] = event['test']
            elif kind == 'error':
                errors.setdefault(event['testID'], []).append(event.get('error', ''))
            elif kind == 'print' and 'EXCEPTION CAUGHT' in event.get('message', ''):
                # A failing widget test prints the exception, then reports only
                # "Test failed. See exception logs above." as its error.
                errors.setdefault(event['testID'], []).append(event['message'])
            elif kind == 'testDone' and event.get('result') != 'success':
                failed.append(event['testID'])

    for test_id in failed:
        test = tests.get(test_id, {})
        # root_url points at the test file when url points into flutter_test.
        path = (repo_path(test.get('root_url') or test.get('url'), workspace)
                or repo_path(suites.get(test.get('suiteID')), workspace))
        line = test.get('root_line') or test.get('line')
        message = '\n\n'.join(errors.get(test_id, [])).strip() or 'The test failed.'
        if len(message) > MAX_MESSAGE:
            message = message[:MAX_MESSAGE] + '\n[truncated]'
        properties = []
        if path:
            properties.append(f'file={escape(path, True)}')
            if line:
                properties.append(f'line={line}')
        properties.append(f"title={escape(test.get('name') or 'Flutter test', True)}")
        print(f"::error {','.join(properties)}::{escape(message)}")


if __name__ == '__main__':
    main(sys.argv[1])
