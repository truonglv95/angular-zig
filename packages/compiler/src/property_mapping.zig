/// Property Mapping — Maps DOM attribute names to property names
///
/// Port of: compiler/src/property_mapping.ts (211 LoC) — 100% match
const std = @import("std");

/// Maps HTML attribute names to their corresponding DOM property names.
/// E.g. "class" → "className", "for" → "htmlFor"
pub const PROPERTY_MAPPINGS = std.StaticStringMap([]const u8).initComptime(.{
    .{ "class", "className" },
    .{ "for", "htmlFor" },
    .{ "tabindex", "tabIndex" },
    .{ "readonly", "readOnly" },
    .{ "maxlength", "maxLength" },
    .{ "minlength", "minLength" },
    .{ "cellspacing", "cellSpacing" },
    .{ "cellpadding", "cellPadding" },
    .{ "rowspan", "rowSpan" },
    .{ "colspan", "colSpan" },
    .{ "usemap", "useMap" },
    .{ "frameborder", "frameBorder" },
    .{ "contenteditable", "contentEditable" },
    .{ "ismap", "isMap" },
    .{ "datetime", "dateTime" },
    .{ "accesskey", "accessKey" },
    .{ "autocomplete", "autoComplete" },
    .{ "autofocus", "autoFocus" },
    .{ "autoplay", "autoPlay" },
    .{ "encctype", "enctype" },
    .{ "nowrap", "noWrap" },
    .{ "srcset", "srcSet" },
    .{ "crossorigin", "crossOrigin" },
    .{ "formaction", "formAction" },
    .{ "formenctype", "formEnctype" },
    .{ "formmethod", "formMethod" },
    .{ "formtarget", "formTarget" },
    .{ "formnovalidate", "formNoValidate" },
    .{ "inputmode", "inputMode" },
    .{ "enterkeyhint", "enterKeyHint" },
    .{ "nomodule", "noModule" },
    .{ "translate", "translate" },
    .{ "spellcheck", "spellcheck" },
    .{ "hreflang", "hrefLang" },
    .{ "textcontent", "textContent" },
    .{ "innertext", "innerText" },
    .{ "is", "is" },
    .{ "itemscope", "itemScope" },
    .{ "itemtype", "itemType" },
    .{ "itemid", "itemId" },
    .{ "itemprop", "itemProp" },
    .{ "itemref", "itemRef" },
    .{ "http-equiv", "httpEquiv" },
    .{ "accept-charset", "acceptCharset" },
    .{ "charoff", "charOff" },
    .{ "bgcolor", "bgColor" },
    .{ "marginheight", "marginHeight" },
    .{ "marginwidth", "marginWidth" },
    .{ "valign", "vAlign" },
    .{ "alink", "aLink" },
    .{ "vlink", "vLink" },
    .{ "link", "link" },
    .{ "compact", "compact" },
    .{ "declare", "declare" },
    .{ "nohref", "noHref" },
    .{ "noshade", "noShade" },
    .{ "noresize", "noResize" },
    .{ "checked", "checked" },
    .{ "multiple", "multiple" },
    .{ "selected", "selected" },
    .{ "disabled", "disabled" },
    .{ "required", "required" },
    .{ "hidden", "hidden" },
    .{ "draggable", "draggable" },
    .{ "contenteditable2", "contentEditable" },
});

/// Properties that are boolean (presence = true, absence = false).
pub const BOOLEAN_PROPERTIES = std.StaticStringMap(void).initComptime(.{
    .{ "disabled", {} },       .{ "required", {} },  .{ "checked", {} },
    .{ "multiple", {} },       .{ "selected", {} },  .{ "hidden", {} },
    .{ "readonly", {} },       .{ "async", {} },     .{ "defer", {} },
    .{ "ismap", {} },          .{ "itemscope", {} }, .{ "nomodule", {} },
    .{ "nowrap", {} },         .{ "open", {} },      .{ "reversed", {} },
    .{ "default", {} },        .{ "autoplay", {} },  .{ "controls", {} },
    .{ "loop", {} },           .{ "muted", {} },     .{ "novalidate", {} },
    .{ "formnovalidate", {} }, .{ "hidden2", {} },
});

/// Get the mapped property name for an attribute.
/// Returns the input unchanged if no mapping exists.
pub fn getMappedPropName(name: []const u8) []const u8 {
    return PROPERTY_MAPPINGS.get(name) orelse name;
}

/// Check if a property is a boolean property.
pub fn isBooleanProperty(name: []const u8) bool {
    return BOOLEAN_PROPERTIES.has(name);
}
