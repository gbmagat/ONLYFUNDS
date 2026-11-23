// A node --test reporter that, on GitHub Actions, prints an error annotation
// for each failing test, so the failure shows up on the commit and pull
// request pages. It prints nothing elsewhere; the spec reporter still writes
// the readable output.
import { relative, sep } from 'node:path';
import { pathToFileURL } from 'node:url';

// The line in `file` where the failing assertion ran, taken from the error's
// stack, so the annotation points at the request that failed rather than at
// the start of the test.
function assertionLine(cause, file) {
  const stack = typeof cause?.stack === 'string' ? cause.stack : '';
  const marker = `${pathToFileURL(file).href}:`;
  const at = stack.indexOf(marker);
  if (at === -1) return undefined;
  const line = Number.parseInt(stack.slice(at + marker.length), 10);
  return Number.isInteger(line) ? line : undefined;
}

function escape(value, isProperty = false) {
  const data = String(value)
    .replaceAll('%', '%25')
    .replaceAll('\r', '%0D')
    .replaceAll('\n', '%0A');
  return isProperty ? data.replaceAll(':', '%3A').replaceAll(',', '%2C') : data;
}

export default async function* githubReporter(source) {
  for await (const { type, data } of source) {
    if (type !== 'test:fail' || process.env.GITHUB_ACTIONS !== 'true') continue;
    const error = data.details?.error;
    // A suite fails when one of its tests fails, and tests are cancelled when
    // a hook fails. The underlying failure already has its own annotation.
    if (['subtestsFailed', 'cancelledByParent'].includes(error?.failureType)) continue;
    const cause = error?.cause ?? error;
    const message =
      cause?.message ?? (typeof cause === 'string' ? cause : 'The test failed.');
    const workspace = process.env.GITHUB_WORKSPACE ?? process.cwd();
    const properties = [];
    if (data.file) {
      properties.push(`file=${escape(relative(workspace, data.file).split(sep).join('/'), true)}`);
      const line = assertionLine(cause, data.file) ?? data.line;
      if (line) properties.push(`line=${line}`);
    }
    properties.push(`title=${escape(data.name, true)}`);
    yield `::error ${properties.join(',')}::${escape(message)}\n`;
  }
}
