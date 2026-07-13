/// Property Mapping — Maps DOM attribute names to property names
///
/// Port of: compiler/src/property_mapping.ts
const std = @import("std");

/// Maps HTML attribute names to their corresponding DOM property names.
/// E.g. "class" → "className", "for" → "htmlFor"
pub const PROPERTY_MAPPINGS = std.StaticStringMap([]const u8).initComptime(.{
    .{ "class", "className" },
    .{ "for", "htmlFor" },
    .{ "tabindex", "tabIndex" },
    .{ "readonly", "readOnly" },
    .{ "maxlength", "maxLength" },
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
    .{ "maxlength", "maxLength" },
    .{ "srcset", "srcSet" },
    .{ "crossorigin", "crossOrigin" },
    .{ "formaction", "formAction" },
    .{ "formenctype", "formEnctype" },
    .{ "formmethod", "formMethod" },
    .{ "formtarget", "formTarget" },
    .{ "inputmode", "inputMode" },
    .{ "enterkeyhint", "enterKeyHint" },
    .{ "nomodule", "noModule" },
    .{ "translate", "translate" },
    .{ "spellcheck", "spellcheck" },
});
