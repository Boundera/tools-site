// CloudFront Function (cloudfront-js-2.0), viewer-request.
//
// This is the only code that runs in front of the bucket. It rewrites paths
// and nothing else: it reads no header, makes no request, and logs nothing.
//
//   /                 -> /site/index.html   the tools index
//   /robots.txt       -> /site/robots.txt   and the other host-level files
//   /<tool>/          -> /<tool>/index.html the tool's page
//   /<tool>           -> 301 to /<tool>/    so the page's links resolve under its prefix
//   anything else with a file extension passes through unchanged
//
// Files a crawler expects at the origin root. They live under site/ with the
// host's other pages, because the bucket policy lets CloudFront read only the
// prefixes it serves, never the bucket root.
var ROOT_FILES = ['/robots.txt', '/sitemap.xml', '/llms.txt', '/favicon.svg'];

function handler(event) {
  var request = event.request;
  var uri = request.uri;

  if (uri === '/' || uri === '/index.html') {
    request.uri = '/site/index.html';
    return request;
  }

  if (ROOT_FILES.indexOf(uri) !== -1) {
    request.uri = '/site' + uri;
    return request;
  }

  if (uri.charAt(uri.length - 1) === '/') {
    request.uri = uri + 'index.html';
    return request;
  }

  var lastSegment = uri.substring(uri.lastIndexOf('/') + 1);
  if (lastSegment.indexOf('.') === -1) {
    return {
      statusCode: 301,
      statusDescription: 'Moved Permanently',
      headers: { location: { value: uri + '/' } },
    };
  }

  return request;
}
