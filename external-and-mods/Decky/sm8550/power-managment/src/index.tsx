import { definePlugin } from "@decky/api";
import { Content } from "./Content";

export default definePlugin(() => ({
  name: "SM8550-Power",
  content: <Content />,
  icon: <div style={{ fontWeight: 700 }}>PWR</div>,
  alwaysRender: true,
}));
