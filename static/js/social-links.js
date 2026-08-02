// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Johan Alvarado

(function () {
    "use strict";

    var links = document.querySelectorAll('.social a[href^="http"]');
    if (!links.length) return;

    var phone = window.matchMedia("(pointer: coarse) and (max-width: 767px)");

    function apply() {
        links.forEach(function (a) {
            if (phone.matches) {
                a.removeAttribute("target");
            } else {
                a.target = "_blank";
                if (a.rel.indexOf("noopener") === -1) {
                    a.rel = (a.rel + " noopener").trim();
                }
            }
        });
    }

    apply();

    if (phone.addEventListener) {
        phone.addEventListener("change", apply);
    } else if (phone.addListener) {
        phone.addListener(apply);
    }
})();
