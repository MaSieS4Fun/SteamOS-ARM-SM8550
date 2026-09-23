import { definePlugin } from "@decky/api";
import { Content } from "./Content";

export default definePlugin(() => ({
  name: "SM8550 LED",
  content: <Content />,
  icon: <div style={{ fontWeight: 700 }}>LED</div>,
  alwaysRender: true,
}));
