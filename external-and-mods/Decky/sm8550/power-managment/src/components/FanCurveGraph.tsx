import { useMemo, useRef, useState } from "react";
import type { PointerEvent as ReactPointerEvent } from "react";
import {
  CURVE_PWM_MAX as PWM_MAX,
  CURVE_PWM_MIN as PWM_MIN,
  CURVE_TEMP_MAX as TEMP_MAX,
  CURVE_TEMP_MIN as TEMP_MIN,
  percentToPwm,
  pwmToPercent,
} from "../lib/fanCurve";
import type { CurvePoint } from "../lib/fanCurve";
import { clamp } from "../lib/util";

const WIDTH = 280;
const HEIGHT = 170;
const PAD_LEFT = 26;
const PAD_RIGHT = 8;
const PAD_TOP = 10;
const PAD_BOTTOM = 18;
const PLOT_W = WIDTH - PAD_LEFT - PAD_RIGHT;
const PLOT_H = HEIGHT - PAD_TOP - PAD_BOTTOM;
const TEMP_TICKS = [0, 20, 40, 60, 80, 100, 120];
const PWM_TICK_PERCENTS = [0, 25, 50, 75, 100];

function xForTemp(temp: number) {
  return PAD_LEFT + ((clamp(temp, TEMP_MIN, TEMP_MAX) - TEMP_MIN) / (TEMP_MAX - TEMP_MIN)) * PLOT_W;
}

function yForPwm(pwm: number) {
  return PAD_TOP + (1 - (clamp(pwm, PWM_MIN, PWM_MAX) - PWM_MIN) / (PWM_MAX - PWM_MIN)) * PLOT_H;
}

interface DragState {
  points: CurvePoint[];
  index: number;
}

export function FanCurveGraph({
  points,
  onChange,
  currentTemp,
}: {
  points: CurvePoint[];
  onChange: (next: CurvePoint[]) => void;
  currentTemp?: number | null;
}) {
  const svgRef = useRef<SVGSVGElement>(null);
  const dragRef = useRef<DragState | null>(null);
  const [livePoints, setLivePoints] = useState<CurvePoint[] | null>(null);
  const [activeIndex, setActiveIndex] = useState<number | null>(null);
  const shown = livePoints ?? points;
  const sorted = useMemo(() => [...shown].sort((a, b) => a.temp - b.temp), [shown]);

  if (!sorted.length) return null;

  const eventToPoint = (e: ReactPointerEvent): CurvePoint | null => {
    const svg = svgRef.current;
    if (!svg) return null;
    const rect = svg.getBoundingClientRect();
    const fracX = clamp((e.clientX - rect.left) / rect.width, 0, 1);
    const fracY = clamp((e.clientY - rect.top) / rect.height, 0, 1);
    const vbX = fracX * WIDTH;
    const vbY = fracY * HEIGHT;
    const temp = Math.round(
      TEMP_MIN + clamp((vbX - PAD_LEFT) / PLOT_W, 0, 1) * (TEMP_MAX - TEMP_MIN),
    );
    const pwm = Math.round(
      PWM_MAX - clamp((vbY - PAD_TOP) / PLOT_H, 0, 1) * (PWM_MAX - PWM_MIN),
    );
    return { temp: clamp(temp, TEMP_MIN, TEMP_MAX), pwm: clamp(pwm, PWM_MIN, PWM_MAX) };
  };

  const onPointerDown = (index: number) => (e: ReactPointerEvent) => {
    e.currentTarget.setPointerCapture(e.pointerId);
    dragRef.current = { points: points.map((p) => ({ ...p })), index };
    setActiveIndex(index);
    setLivePoints(points.map((p) => ({ ...p })));
  };

  const onPointerMove = (e: ReactPointerEvent) => {
    const drag = dragRef.current;
    if (!drag) return;
    const next = eventToPoint(e);
    if (!next) return;
    drag.points[drag.index] = next;
    setLivePoints([...drag.points]);
  };

  const endDrag = (e: ReactPointerEvent) => {
    const drag = dragRef.current;
    if (!drag) return;
    dragRef.current = null;
    setActiveIndex(null);
    setLivePoints(null);
    onChange(drag.points);
    try {
      e.currentTarget.releasePointerCapture(e.pointerId);
    } catch {
      // already released
    }
  };

  const first = sorted[0];
  const last = sorted[sorted.length - 1];
  const pathD = [
    `M ${PAD_LEFT} ${yForPwm(first.pwm)}`,
    `L ${xForTemp(first.temp)} ${yForPwm(first.pwm)}`,
    ...sorted.slice(1).map((p) => `L ${xForTemp(p.temp)} ${yForPwm(p.pwm)}`),
    `L ${PAD_LEFT + PLOT_W} ${yForPwm(last.pwm)}`,
  ].join(" ");

  const fanStopActive = first.pwm === 0;
  let fanStopBoundaryTemp = first.temp;
  for (const point of sorted) {
    if (point.pwm !== 0) break;
    fanStopBoundaryTemp = point.temp;
  }
  const fanStopX = xForTemp(fanStopBoundaryTemp);

  const hasCurrentTemp = typeof currentTemp === "number" && Number.isFinite(currentTemp);
  const currentTempX = hasCurrentTemp ? xForTemp(currentTemp) : 0;

  const interpolatePwm = (temp: number) => {
    if (temp <= first.temp) return first.pwm;
    if (temp >= last.temp) return last.pwm;
    for (let i = 0; i < sorted.length - 1; i += 1) {
      const a = sorted[i];
      const b = sorted[i + 1];
      if (temp >= a.temp && temp <= b.temp) {
        const t = b.temp === a.temp ? 0 : (temp - a.temp) / (b.temp - a.temp);
        return a.pwm + t * (b.pwm - a.pwm);
      }
    }
    return last.pwm;
  };
  const currentTempY = hasCurrentTemp ? yForPwm(interpolatePwm(currentTemp)) : 0;

  return (
    <svg
      ref={svgRef}
      viewBox={`0 0 ${WIDTH} ${HEIGHT}`}
      width="100%"
      style={{ display: "block", touchAction: "none" }}
      onPointerMove={onPointerMove}
      onPointerUp={endDrag}
      onPointerCancel={endDrag}
    >
      <rect x={PAD_LEFT} y={PAD_TOP} width={PLOT_W} height={PLOT_H} fill="rgba(255,255,255,0.04)" rx={4} />

      {fanStopActive ? (
        <>
          <rect x={PAD_LEFT} y={PAD_TOP} width={fanStopX - PAD_LEFT} height={PLOT_H} fill="rgba(92,200,255,0.08)" />
          <text x={PAD_LEFT + 4} y={PAD_TOP + 12} fill="#5cc8ff" fontSize={9} opacity={0.8}>
            FAN STOPPED
          </text>
        </>
      ) : null}

      {PWM_TICK_PERCENTS.map((percent) => {
        const pwm = percentToPwm(percent);
        return (
          <g key={percent}>
            <line
              x1={PAD_LEFT}
              y1={yForPwm(pwm)}
              x2={PAD_LEFT + PLOT_W}
              y2={yForPwm(pwm)}
              stroke="rgba(255,255,255,0.08)"
              strokeWidth={1}
            />
            <text x={2} y={yForPwm(pwm) + 3} fill="rgba(255,255,255,0.45)" fontSize={8}>
              {`${percent}%`}
            </text>
          </g>
        );
      })}

      {TEMP_TICKS.map((temp) => (
        <g key={temp}>
          <line
            x1={xForTemp(temp)}
            y1={PAD_TOP}
            x2={xForTemp(temp)}
            y2={PAD_TOP + PLOT_H}
            stroke="rgba(255,255,255,0.08)"
            strokeWidth={1}
          />
          <text x={xForTemp(temp) - 6} y={HEIGHT - 2} fill="rgba(255,255,255,0.45)" fontSize={8}>
            {temp}
          </text>
        </g>
      ))}

      <path d={pathD} fill="none" stroke="#1a9fff" strokeWidth={2} />

      {hasCurrentTemp ? (
        <>
          <line
            x1={currentTempX}
            y1={PAD_TOP}
            x2={currentTempX}
            y2={PAD_TOP + PLOT_H}
            stroke="#ffd166"
            strokeWidth={1.5}
            strokeDasharray="4 3"
          />
          <circle cx={currentTempX} cy={currentTempY} r={4} fill="#ffd166" />
          <text x={currentTempX + 6} y={currentTempY - 6} fill="#ffd166" fontSize={9}>
            {`${currentTemp}°C`}
          </text>
        </>
      ) : null}

      {sorted.map((point) => {
        const index = shown.indexOf(point);
        const isActive = activeIndex !== null && shown[activeIndex] === point;
        return (
          <g key={`${point.temp}-${point.pwm}-${index}`}>
            <circle
              cx={xForTemp(point.temp)}
              cy={yForPwm(point.pwm)}
              r={isActive ? 7 : 5}
              fill={isActive ? "#ffd166" : "#1a9fff"}
              stroke="#fff"
              strokeWidth={1}
              style={{ cursor: "grab" }}
              onPointerDown={onPointerDown(index)}
            />
            {isActive ? (
              <text
                x={xForTemp(point.temp) + 8}
                y={yForPwm(point.pwm) - 8}
                fill="#ffd166"
                fontSize={9}
              >
                {`${point.temp}°C / ${pwmToPercent(point.pwm)}%`}
              </text>
            ) : null}
          </g>
        );
      })}
    </svg>
  );
}
