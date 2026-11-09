import Foundation

nonisolated enum MarkdownPreviewScripts {
    static let positionAttribute = "md-src-pos"
    static let followTimeMilliseconds = 40

    static let pageScript = #"""
    (function () {
      if (window.dreamderPreview) {
        return;
      }
      var FOLLOW_TIME_MS = \#(followTimeMilliseconds);
      var ATTRIBUTE = "\#(positionAttribute)";
      var USER_IDENTIFIER_PREFIX = "\#(MarkdownHTMLSanitizer.userIdentifierPrefix)";
      var targetOffset = 0;
      var hasTarget = false;
      var isFrameRequested = false;
      var followY = null;
      var appliedY = 0;
      var lastFrameTime = 0;

      function rangeOf(node) {
        var value = node.getAttribute ? node.getAttribute(ATTRIBUTE) : null;
        if (!value) {
          return null;
        }
        var parts = value.split("..");
        var from = Number(parts[0]);
        var to = Number(parts[1]);
        if (isNaN(from) || isNaN(to)) {
          return null;
        }
        return { from: from, to: to };
      }

      function collectPositioned(node, start, end, result) {
        for (var child = node.firstElementChild; child !== null; child = child.nextElementSibling) {
          var range = rangeOf(child);
          if (!range) {
            if (child.tagName === "THEAD" || child.tagName === "TBODY") {
              collectPositioned(child, start, end, result);
            }
            continue;
          }
          if (range.to < start.offset || range.from > end.offset || child.getClientRects().length === 0) {
            continue;
          }
          result.push({ element: child, from: range.from, to: range.to });
        }
        return result;
      }

      function documentEndOffset() {
        var last = -1;
        for (var child = document.body.firstElementChild; child !== null; child = child.nextElementSibling) {
          var range = rangeOf(child);
          if (range && range.to > last) {
            last = range.to;
          }
        }
        return last;
      }

      function sourceOffsetToY(offset) {
        var lastOffset = documentEndOffset();
        if (lastOffset < 0) {
          return null;
        }
        var start = { offset: 0, y: 0 };
        var end = { offset: lastOffset, y: document.documentElement.scrollHeight };
        var node = document.body;
        while (node !== null) {
          var children = collectPositioned(node, start, end, []);
          if (children.length === 0) {
            break;
          }
          var container = null;
          for (var i = 0; i < children.length; i++) {
            var child = children[i];
            var box = child.element.getBoundingClientRect();
            var top = box.top + window.scrollY;
            var bottom = box.bottom + window.scrollY;
            if (offset < child.from) {
              end = { offset: child.from, y: top };
              break;
            }
            if (offset <= child.to) {
              container = child.element;
              start = { offset: child.from, y: top };
              end = { offset: child.to, y: bottom };
              break;
            }
            start = { offset: child.to, y: bottom };
          }
          node = container;
        }
        var length = end.offset - start.offset;
        var fraction = length > 0 ? Math.min(Math.max((offset - start.offset) / length, 0), 1) : 0;
        return start.y + fraction * Math.max(end.y - start.y, 0);
      }

      function followTarget() {
        var y = sourceOffsetToY(targetOffset);
        if (y === null) {
          return null;
        }
        var root = document.scrollingElement;
        return Math.min(Math.max(y, 0), Math.max(root.scrollHeight - root.clientHeight, 0));
      }

      function followFrame(time) {
        var target = followTarget();
        if (target === null || (followY !== null && Math.abs(window.scrollY - appliedY) > 1)) {
          followY = null;
          isFrameRequested = false;
          return;
        }
        var current = followY !== null ? followY : window.scrollY;
        var elapsed = Math.min(Math.max(time - lastFrameTime, 0), 100);
        lastFrameTime = time;
        var next = current + (target - current) * (1 - Math.exp(-elapsed / FOLLOW_TIME_MS));
        var isDone = Math.abs(target - next) < 0.5;
        followY = isDone ? null : next;
        window.scrollTo({ top: isDone ? target : next, behavior: "instant" });
        appliedY = window.scrollY;
        if (isDone) {
          isFrameRequested = false;
          return;
        }
        requestAnimationFrame(followFrame);
      }

      function scrollToSourceOffset(offset) {
        targetOffset = offset;
        hasTarget = true;
        if (isFrameRequested) {
          return;
        }
        isFrameRequested = true;
        lastFrameTime = performance.now();
        requestAnimationFrame(followFrame);
      }

      function replaceBody(html, follow) {
        var y = window.scrollY;
        document.body.innerHTML = html;
        window.scrollTo(0, y);
        if (follow && hasTarget) {
          followY = null;
          scrollToSourceOffset(targetOffset);
        }
      }

      function scrollToAnchor(identifier) {
        var element = document.getElementById(identifier)
          || document.getElementById(USER_IDENTIFIER_PREFIX + identifier);
        if (element) {
          element.scrollIntoView();
        }
      }

      window.dreamderPreview = {
        scrollToSourceOffset: scrollToSourceOffset,
        replaceBody: replaceBody,
        scrollToAnchor: scrollToAnchor
      };
    })();
    """#

    static func scrollScript(offset: Int) -> String {
        "window.dreamderPreview && window.dreamderPreview.scrollToSourceOffset(\(offset));"
    }

    static func replaceBodyScript(bodyLiteral: String, follow: Bool) -> String {
        "window.dreamderPreview && window.dreamderPreview.replaceBody(\(bodyLiteral), \(follow));"
    }

    static func anchorScript(identifierLiteral: String) -> String {
        "window.dreamderPreview && window.dreamderPreview.scrollToAnchor(\(identifierLiteral));"
    }
}
