-- Reproducible Local Repository Button - Quarto Extension
-- Generates repository button complementary to the ``cslovell/reproducible`` extension

-- ============================================
-- CONFIGURATION & HELPER FUNCTIONS
-- ============================================

-- Get configuration with fallback chain: document > project > extension defaults
local function get_config(meta)
  local config = meta["reproducible-local-config"] or {}
  local reproducible_config = meta["reproducible-config"] or {}
  
  -- Try to inherit branding and UI from reproducible-config if not set
  local branding = config.branding or reproducible_config.branding or {}
  local ui = config.ui or reproducible_config.ui or {}
  
  return {
    repository = config.repository or {},
    ui = ui,
    branding = branding
  }
end

-- Safe metadata extraction with default
local function get_meta_string(meta, key, default)
  if meta and meta[key] then
    return pandoc.utils.stringify(meta[key])
  end
  return default
end

-- Get value with precedence: document > config > fallback
local function get_value(doc_meta, config, key, fallback)
  local value = get_meta_string(doc_meta, key)
  if value then return value end

  value = get_meta_string(config, key)
  if value then return value end

  return fallback
end

-- Generate HTML button markup based on notice style
local function generate_button_html(repo_url, meta, config)
  -- Get UI configuration
  local button_text = get_meta_string(meta["reproducible-local"], "button-text") or get_meta_string(config.repository, "button-text", "View Repository")
  local notice_title = get_meta_string(config.ui, "notice-title", "Files for local reproduction")
  local notice_description = get_meta_string(config.ui, "notice-description", "If you prefer, you can get the chapter files and reproduce in your own environment.")
  local notice_style = get_meta_string(meta["reproducible-local"], "notice-style") or get_meta_string(config.ui, "notice-style", "full")

  -- Get branding (use gray as default, with fallback to reproducible extension defaults)
  local primary_color = get_meta_string(config.branding, "primary-color", "#6c757d")
  local text_color = get_meta_string(config.branding, "text-color", "rgb(44, 50, 63)")
  local bg_color = get_meta_string(config.branding, "background-color", "#fafafa")

  -- Generate HTML based on notice style (same structure as reproducible extension)
  if notice_style == "button-only" then
    -- Just the button, no wrapper
    return string.format([[
        <a href="%s"
           target="_blank"
           class="reproducible-local-button"
           style="background: %s; color: white; padding: 6px 14px; text-decoration: none; border-radius: 3px; font-size: 0.9rem; font-weight: 500; display: inline-block; margin: 20px 0;">
          %s
        </a>
      ]], repo_url, primary_color, button_text
    )

  elseif notice_style == "minimal" then
    -- Button + metadata, no title
    return string.format([[
        <div class="reproducible-local-notice minimal" style="border-left: 3px solid %s; background: %s; padding: 12px 16px; margin: 20px 0 30px 0; font-size: 0.95rem; color: %s;">
          <div style="display: flex; align-items: center; gap: 12px; flex-wrap: wrap;">
            <a href="%s"
               target="_blank"
               style="background: %s; color: white; padding: 6px 14px; text-decoration: none; border-radius: 3px; font-size: 0.9rem; font-weight: 500; display: inline-block;">
              %s
            </a>
          </div>
        </div>
      ]], primary_color, bg_color, text_color, repo_url, primary_color, button_text
    )

  else
    -- "full" style (default) - Title + description + button
    return string.format([[
        <div class="reproducible-local-notice full" style="border-left: 3px solid %s; background: %s; padding: 12px 16px; margin: 20px 0 30px 0; font-size: 0.95rem; color: %s;">
          <div style="margin-bottom: 6px;">
            <strong>%s</strong>
          </div>
          <div style="margin-bottom: 8px; color: #666; font-size: 0.9rem;">
            %s
          </div>
          <div style="display: flex; align-items: center; gap: 12px; flex-wrap: wrap;">
            <a href="%s"
               target="_blank"
               style="background: %s; color: white; padding: 6px 14px; text-decoration: none; border-radius: 3px; font-size: 0.9rem; font-weight: 500; display: inline-block;">
              %s
            </a>
          </div>
        </div>
    ]], primary_color, bg_color, text_color, notice_title, notice_description, repo_url, primary_color, button_text
   )
  end
end

-- ============================================
-- MAIN FILTER FUNCTION
-- ============================================

function Meta(meta)
  -- Only inject for HTML output
  if not quarto.doc.is_format("html") then
    return meta
  end

  -- Check if feature is enabled
  if not meta["reproducible-local"] then
    return meta
  end

  if not meta["reproducible-local"].enabled then
    return meta
  end

  -- Get configuration
  local config = get_config(meta)

  -- Get repository URL with precedence
  local repo_url = get_meta_string(meta["reproducible-local"], "repository-url") or get_meta_string(config.repository, "url")
  
  if not repo_url or repo_url == "" then
    quarto.log.warning("reproducible-local: repository URL not specified. Button will not be displayed.")
    return meta
  end

  -- Generate HTML
  local html = generate_button_html(repo_url, meta, config)

  -- Inject into document (before body content, after reproducible button if present)
  quarto.doc.include_text("before-body", html)

  return meta
end

-- Export the filter
return {{Meta = Meta}}
