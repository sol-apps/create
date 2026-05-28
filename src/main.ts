import "./styles/base.css";
import "./styles/layout.css";
import "./styles/card.css";
import "./styles/readme.css";
import "./styles/states.css";

import { loadGallery } from "./gallery";
import { initTheme } from "./theme";

const themeToggle = document.getElementById("themeToggle") as HTMLButtonElement | null;
const gallery = document.getElementById("gallery");
const prompt = document.getElementById("prompt");

if (themeToggle) initTheme(themeToggle);
if (gallery) void loadGallery(gallery, prompt);
