# frozen_string_literal: true

class RubyCrawl
  class Browser
    # JavaScript extraction constants, evaluated inside Chromium via page.evaluate().
    # Ported verbatim from node/src/index.js — logic is unchanged.
    # NOISE_SELECTORS is interpolated directly into EXTRACT_CONTENT_JS (no need to
    # pass as a JS argument as the Node version did).
    module Extraction
      # All constants are IIFEs — Ferrum's page.evaluate() evaluates an expression,
      # it does NOT call function definitions. Wrapping as (() => { ... })() ensures
      # the function is immediately invoked and its return value is captured.
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

      # Semantic noise selectors — covers standard HTML5 elements and ARIA roles.
      # Interpolated directly into EXTRACT_CONTENT_JS as a string literal.
      NOISE_SELECTORS = [
        'nav', 'header', 'footer', 'aside',
        '[role="navigation"]', '[role="banner"]', '[role="contentinfo"]',
        '[role="complementary"]', '[role="dialog"]', '[role="tooltip"]',
        '[role="alert"]', '[aria-hidden="true"]',
        'script', 'style', 'noscript', 'iframe'
      ].join(', ').freeze

      # Removes semantic noise (nav/header/footer/aside + ARIA roles) and high
      # link-density containers, then returns both clean plain text and clean HTML.
      # DOM mutations are reversed after extraction so the page is unchanged.
      EXTRACT_CONTENT_JS = <<~JS.freeze
        (() => {
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
          return { cleanHtml };
        })()
      JS
    end
  end
end
