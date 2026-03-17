# frozen_string_literal: true

class RubyCrawl
  class Browser
    # JavaScript extraction constants, evaluated inside Chromium via page.evaluate().
    # All constants are IIFEs — Ferrum's page.evaluate() evaluates an expression,
    # it does NOT call function definitions. Wrapping as (() => { ... })() ensures
    # the function is immediately invoked and its return value is captured.
    module Extraction
      EXTRACT_METADATA_JS = <<~JS
        (() => {
          const getMeta = (name) => {
            const meta = document.querySelector(`meta[name="${name}"], meta[property="${name}"]`);
            return meta?.getAttribute("content") || null;
          };
          const getLink = (rel) => {
            const link = document.querySelector(`link[rel="${rel}"]`);
            return link?.getAttribute("href") || null;
          };
          return {
            title:               document.title || null,
            description:         getMeta("description") || getMeta("og:description") || null,
            keywords:            getMeta("keywords"),
            author:              getMeta("author"),
            og_title:            getMeta("og:title"),
            og_description:      getMeta("og:description"),
            og_image:            getMeta("og:image"),
            og_url:              getMeta("og:url"),
            og_type:             getMeta("og:type"),
            twitter_card:        getMeta("twitter:card"),
            twitter_title:       getMeta("twitter:title"),
            twitter_description: getMeta("twitter:description"),
            twitter_image:       getMeta("twitter:image"),
            canonical:           getLink("canonical"),
            lang:                document.documentElement.lang || null,
            charset:             document.characterSet || null,
          };
        })()
      JS

      EXTRACT_LINKS_JS = <<~JS
        (() => Array.from(document.querySelectorAll("a[href]")).map(link => ({
          url:   link.href,
          text:  (link.textContent || "").trim(),
          title: link.getAttribute("title") || null,
          rel:   link.getAttribute("rel")   || null,
        })))()
      JS

      EXTRACT_RAW_TEXT_JS = <<~JS
        (() => (document.body?.innerText || "").trim())()
      JS

      # Semantic noise selectors — used by the heuristic fallback.
      NOISE_SELECTORS = [
        'nav', 'header', 'footer', 'aside',
        '[role="navigation"]', '[role="banner"]', '[role="contentinfo"]',
        '[role="complementary"]', '[role="dialog"]', '[role="tooltip"]',
        '[role="alert"]', '[aria-hidden="true"]',
        'script', 'style', 'noscript', 'iframe'
      ].join(', ').freeze

      # Mozilla Readability.js v0.6.0 — vendored source, read once at load time.
      # Embedded inside EXTRACT_CONTENT_JS's outer IIFE so Readability is defined
      # and used within the same Runtime.evaluate expression (Ferrum evaluates a
      # single expression — separate evaluate calls have separate scopes).
      READABILITY_JS = File.read(File.join(__dir__, 'readability.js')).freeze

      # Extracts clean article HTML using Mozilla Readability (primary) with a
      # link-density heuristic as fallback when Readability returns no content.
      # Everything is wrapped in one outer IIFE so page.evaluate gets a single
      # expression and Readability is in scope for the extraction logic.
      # DOM mutations from the fallback path are reversed after extraction.
      EXTRACT_CONTENT_JS = <<~JS.freeze
        (() => {
          // Mozilla Readability.js v0.6.0 — defined in this IIFE's scope.
          #{READABILITY_JS}

          // Primary: Mozilla Readability — article-quality extraction.
          let readabilityDebug = null;
          try {
            const docClone = document.cloneNode(true);
            const reader = new Readability(docClone, { charThreshold: 100 });
            const article = reader.parse();
            if (article && article.textContent && article.textContent.trim().length > 200) {
              return { cleanHtml: article.content, extractor: "readability" };
            }
            readabilityDebug = article ? `returned ${article.textContent?.trim().length ?? 0} text chars (below threshold)` : "returned null (no article detected)";
          } catch (e) {
            readabilityDebug = `error: ${e.message}`;
          }

          // Fallback: link-density heuristic (works on nav-heavy / non-article pages).
          const noiseSelectors = #{NOISE_SELECTORS.to_json};
          function linkDensity(el) {
            const total = (el.innerText || "").trim().length;
            if (!total) return 1;
            const linked = Array.from(el.querySelectorAll("a"))
              .reduce((sum, a) => sum + (a.innerText || "").trim().length, 0);
            return linked / total;
          }
          const removed = [];
          function stash(el) {
            if (el.parentNode) {
              removed.push({ el, parent: el.parentNode, next: el.nextSibling });
              el.parentNode.removeChild(el);
            }
          }
          document.body.querySelectorAll(noiseSelectors).forEach(stash);
          const blockTags = new Set(["script", "style", "noscript", "link", "meta"]);
          const topChildren = Array.from(document.body.children)
            .filter(el => !blockTags.has(el.tagName.toLowerCase()));
          const roots = topChildren.length === 1
            ? [document.body, topChildren[0]] : [document.body];
          for (const root of roots) {
            for (const el of Array.from(root.children)) {
              const text = (el.innerText || "").trim();
              if (text.length >= 20 && linkDensity(el) > 0.5) stash(el);
            }
          }
          const cleanHtml = document.body.innerHTML;
          removed.reverse().forEach(({ el, parent, next }) => parent.insertBefore(el, next));
          return { cleanHtml, extractor: "heuristic", debug: readabilityDebug };
        })()
      JS
    end
  end
end
