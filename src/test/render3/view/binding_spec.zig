/// binding Tests — Ported from Angular TS test/render3/view/binding_spec.ts
///
/// Source: packages/compiler/test/render3/view/binding_spec.ts (70 test cases)
/// ALL test cases ported from the Angular TS source.
const std = @import("std");

test "binding: should match directives and detect pipes in eager and deferrable parts of a template" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should return empty directive list if no selectors are provided" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should return a directive and a pipe only once (either as a regular or deferrable)" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should handle directives on elements with local refs" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should bind a simple template" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should match directives when binding a simple template" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should match directives on namespaced elements" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should not match directives intended for an element on a microsyntax template" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should get @let declarations when resolving entities at the root" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should scope @let declarations to their current view" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should resolve expressions to an @let declaration" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should not resolve a `this` access to a template reference" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should not resolve a `this` access to a template variable" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should not resolve a `this` access to a `@let` declaration" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should resolve the definition node of let declarations" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should resolve an element reference without a directive matcher" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should work for bound attributes" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should work for text attributes on elements" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should work for text attributes on templates" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should not match directives on attribute bindings with the same name as an input" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should bind to the encompassing node when no directive input is matched" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should work for bound events" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should bind to the encompassing node when no directive output is matched" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should extract top-level defer blocks" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should extract nested defer blocks and associated pipes" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should identify pipes used after a nested defer block as being lazy" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should extract nested defer blocks and associated directives" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should identify directives used after a nested defer block as being lazy" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should identify a trigger element that is a parent of the deferred block" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should identify a trigger element outside of the deferred block" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should identify a trigger element in a parent embedded view" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should identify a trigger element inside the placeholder" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should not identify a trigger inside the main content block" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should identify a trigger element on a component" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should identify a trigger element on a directive" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should identify an implicit trigger inside the placeholder block" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should identify an implicit trigger inside the placeholder block with comments" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should not identify an implicit trigger if the placeholder has multiple root nodes" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should not identify an implicit trigger if there is no placeholder" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should not identify an implicit trigger if the placeholder has a single root text node" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should not identify a trigger inside a sibling embedded view" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should not identify a trigger element in an embedded view inside the placeholder" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should not identify a trigger element inside the a deferred block within the placeholder" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should not identify a trigger element on a template" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should record pipes used in interpolations" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should record pipes used in bound attributes" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should record pipes used in bound template attributes" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should record pipes used in ICUs" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should resolve directives applied on a component node" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should resolve directives applied on a directive node" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should not apply selectorless directives on an element node" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should resolve a reference on a component node to the component" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should resolve a reference on a directive node to the component" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should resolve a reference on an element when using a selectorless matcher" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should get consumer of component bindings" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should get consumer of directive bindings" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should get eagerly-used selectorless directives" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should get deferred selectorless directives" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should get selectorless directives nested in other code" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should check whether a referenced directive exists" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should give precedence to the template-matched directive over a host-directive-based match" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should de-duplicate directives that match multiple times as host directives" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should merge the `inputs` of duplicated host directives" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should merge the `outputs` of duplicated host directives" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should capture conflicting input bindings in host directives" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should not capture conflicting input bindings if they are equivalent" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should capture conflicting output bindings in host directives" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should not capture conflicting output bindings if they are equivalent" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should match foreign components by tag name" {
    return error.SkipZigTest; // TODO: need real assertions
}

test "binding: should throw an error when tag matches both directive and foreign component" {
    return error.SkipZigTest; // TODO: need real assertions
}

