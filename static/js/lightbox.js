// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Johan Alvarado

(function () {
    "use strict";

    var tpl = document.getElementById("tpl-lightbox");
    if (!tpl) return;

    var images = document.querySelectorAll("main p > img");
    if (!images.length) return;

    var dialog = tpl.content.firstElementChild.cloneNode(true);
    if (typeof dialog.showModal !== "function") return;

    var frame = dialog.querySelector(".lightbox-image");
    var caption = dialog.querySelector(".lightbox-caption");
    var closeButton = dialog.querySelector(".lightbox-close");
    document.body.appendChild(dialog);

    function captionFor(img) {
        var next = img.parentNode.nextElementSibling;
        if (!next || next.tagName !== "P") return "";

        var em = next.firstElementChild;
        if (!em || em.tagName !== "EM") return "";
        if (next.textContent.trim() !== em.textContent.trim()) return "";

        return em.textContent.trim();
    }

    function expand(img) {
        frame.src = img.currentSrc || img.src;
        frame.alt = img.alt;
        caption.textContent = captionFor(img);
        dialog.showModal();
    }

    images.forEach(function (img) {
        img.setAttribute("role", "button");
        img.setAttribute("tabindex", "0");
        img.setAttribute("aria-haspopup", "dialog");
        img.title = "Expand image";

        img.addEventListener("click", function () { expand(img); });

        img.addEventListener("keydown", function (event) {
            if (event.key === "Enter" || event.key === " ") {
                event.preventDefault();
                expand(img);
            }
        });
    });

    closeButton.addEventListener("click", function () { dialog.close(); });

    dialog.addEventListener("click", function (event) {
        if (event.target === dialog) dialog.close();
    });

    dialog.addEventListener("close", function () {
        frame.removeAttribute("src");
        caption.textContent = "";
    });
})();
