// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Johan Alvarado

(function () {
    "use strict";

    var tpl = document.getElementById("tpl-copy-button");
    if (!tpl) return;

    function copyText(text) {
        if (navigator.clipboard && window.isSecureContext) {
            return navigator.clipboard.writeText(text);
        }
        return new Promise(function (resolve, reject) {
            var ta = document.createElement("textarea");
            ta.value = text;
            ta.setAttribute("readonly", "");
            ta.style.position = "fixed";
            ta.style.top = "-1000px";
            document.body.appendChild(ta);
            ta.select();
            var ok = false;
            try { ok = document.execCommand("copy"); } catch (e) {}
            document.body.removeChild(ta);
            ok ? resolve() : reject(new Error("copy failed"));
        });
    }

    document.querySelectorAll("pre").forEach(function (pre) {
        var wrapper = document.createElement("div");
        wrapper.className = "code-block";
        pre.parentNode.insertBefore(wrapper, pre);
        wrapper.appendChild(pre);

        var btn = tpl.content.firstElementChild.cloneNode(true);
        wrapper.appendChild(btn);

        var timer;
        btn.addEventListener("click", function () {
            copyText(pre.innerText).then(function () {
                setState("copied", "Copied");
            }, function () {
                setState("error", "Copy failed");
            });
        });

        function setState(state, label) {
            clearTimeout(timer);
            btn.dataset.state = state;
            btn.setAttribute("aria-label", label);
            btn.title = label;
            timer = setTimeout(function () {
                delete btn.dataset.state;
                btn.setAttribute("aria-label", "Copy code");
                btn.title = "Copy code";
            }, 1600);
        }
    });
})();
