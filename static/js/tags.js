// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Johan Alvarado

(function () {
    "use strict";

    function searchIn(panel) {
        var form = panel.querySelector(".tag-search");
        if (!form) return null;

        var input = form.querySelector(".tag-query");
        var send = form.querySelector(".tag-go");
        var empty = panel.querySelector(".tag-empty");

        var items = [];
        panel.querySelectorAll(".tag[data-tag]").forEach(function (link) {
            items.push({
                link: link,
                row: link.closest("li") || link,
                name: link.dataset.tag.toLowerCase()
            });
        });

        function resolve(query) {
            var hits = items.filter(function (item) {
                return item.name.indexOf(query) !== -1;
            });
            var exact = hits.filter(function (item) { return item.name === query; });
            if (exact.length) return exact[0];
            return hits.length === 1 ? hits[0] : null;
        }

        function firstHit(query) {
            for (var i = 0; i < items.length; i++) {
                if (items[i].name.indexOf(query) !== -1) return items[i];
            }
            return null;
        }

        function refresh() {
            var query = input.value.trim().toLowerCase();
            var target = query ? resolve(query) : null;
            var shown = 0;

            items.forEach(function (item) {
                var hit = !query || item.name.indexOf(query) !== -1;
                item.row.hidden = !hit;
                item.link.classList.toggle("is-match", item === target);
                if (hit) shown++;
            });

            send.disabled = !target;
            if (empty) empty.hidden = shown !== 0;
        }

        input.addEventListener("input", refresh);

        input.addEventListener("keydown", function (e) {
            if (e.key !== "Tab" || e.shiftKey) return;

            var query = input.value.trim().toLowerCase();
            var first = query ? firstHit(query) : null;
            if (!first || first.name === query) return;

            e.preventDefault();
            input.value = first.link.dataset.tag;
            refresh();
        });

        form.addEventListener("submit", function (e) {
            e.preventDefault();
            var target = resolve(input.value.trim().toLowerCase());
            if (target) window.location.href = target.link.href;
        });

        return {
            focus: function () { input.focus(); },
            reset: function () {
                input.value = "";
                refresh();
            }
        };
    }

    var pairs = [];

    document.querySelectorAll(".tag-toggle, .filter-toggle, .menu-toggle").forEach(function (btn) {
        var panel = document.getElementById(btn.getAttribute("aria-controls"));
        if (!panel) return;
        var pair = { btn: btn, panel: panel, search: searchIn(panel) };
        pairs.push(pair);

        btn.addEventListener("click", function () {
            var wasOpen = btn.getAttribute("aria-expanded") === "true";
            closeAll();
            if (!wasOpen) open(pair);
        });
    });

    if (!pairs.length) return;

    function open(pair) {
        pair.btn.setAttribute("aria-expanded", "true");
        pair.panel.classList.add("is-open");
        if (pair.search) pair.search.focus();
    }

    function close(pair) {
        pair.btn.setAttribute("aria-expanded", "false");
        pair.panel.classList.remove("is-open");
        if (pair.search) pair.search.reset();
    }

    function closeAll() {
        pairs.forEach(close);
    }

    document.addEventListener("click", function (e) {
        pairs.forEach(function (pair) {
            if (!pair.btn.contains(e.target) && !pair.panel.contains(e.target)) close(pair);
        });
    });

    document.addEventListener("keydown", function (e) {
        if (e.key !== "Escape") return;
        pairs.forEach(function (pair) {
            if (!pair.panel.classList.contains("is-open")) return;
            close(pair);
            pair.btn.focus();
        });
    });
})();
