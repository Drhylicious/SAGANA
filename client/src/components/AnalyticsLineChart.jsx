
import React from 'react';

const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];


const AnalyticsLineChart = ({ data, maxValue }) => {
  if (!data || data.length === 0) {
    return <div className="text-gray-400 text-sm text-center py-4">No data available.</div>;
  }

  const maxY = maxValue || Math.max(...data, 1);
  const hasData = data.some(v => v > 0);

  const width = 560;
  const height = 160;
  const paddingLeft = 40;
  const paddingRight = 20;
  const paddingTop = 20;
  const paddingBottom = 30;
  const chartWidth = width - paddingLeft - paddingRight;
  const chartHeight = height - paddingTop - paddingBottom;

  const getX = (i) => paddingLeft + (i / 11) * chartWidth;
  const getY = (val) => paddingTop + chartHeight - (val / maxY) * chartHeight;

  const points = data.map((y, i) => `${getX(i)},${getY(y)}`).join(' ');

  return (
    <div className="w-full overflow-x-auto">
      <svg width="100%" viewBox={`0 0 ${width} ${height}`} className="block">
        {/* Grid lines */}
        {[0, 0.25, 0.5, 0.75, 1].map((ratio) => {
          const y = paddingTop + chartHeight - ratio * chartHeight;
          return (
            <g key={ratio}>
              <line x1={paddingLeft} y1={y} x2={width - paddingRight} y2={y} stroke="#f0f0f0" strokeWidth="1" />
              <text x={paddingLeft - 5} y={y + 4} fontSize="9" textAnchor="end" fill="#aaa">
                {Math.round(maxY * ratio)}
              </text>
            </g>
          );
        })}

        {/* Axes */}
        <line x1={paddingLeft} y1={paddingTop + chartHeight} x2={width - paddingRight} y2={paddingTop + chartHeight} stroke="#ccc" strokeWidth="1.5" />
        <line x1={paddingLeft} y1={paddingTop} x2={paddingLeft} y2={paddingTop + chartHeight} stroke="#ccc" strokeWidth="1.5" />

        {!hasData && (
          <text x={width / 2} y={height / 2} fontSize="12" textAnchor="middle" fill="#aaa">
            No harvest data logged yet
          </text>
        )}

        {/* Area fill */}
        {hasData && (
          <polyline
            fill="rgba(22, 163, 74, 0.1)"
            stroke="none"
            points={`${getX(0)},${paddingTop + chartHeight} ${points} ${getX(11)},${paddingTop + chartHeight}`}
          />
        )}

        {/* Line */}
        {hasData && (
          <polyline fill="none" stroke="#16a34a" strokeWidth="2.5" points={points} />
        )}

        {/* Dots */}
        {data.map((y, i) => (
          <circle key={i} cx={getX(i)} cy={getY(y)} r={y > 0 ? 4 : 2.5}
            fill={y > 0 ? "#16a34a" : "#ccc"} />
        ))}

        {/* Month labels */}
        {months.map((m, i) => (
          <text key={m} x={getX(i)} y={height - 5} fontSize="10" textAnchor="middle" fill="#888">{m}</text>
        ))}
      </svg>
    </div>
  );
};

export default AnalyticsLineChart;
