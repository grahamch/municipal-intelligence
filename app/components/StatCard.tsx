interface StatCardProps {
    label: string
    value: string
    valueColour?: string
  }
  
  export default function StatCard({ label, value, valueColour = "text-gray-900" }: StatCardProps) {
    return (
      <div className="bg-white rounded-lg p-6 shadow-sm">
        <p className="text-sm text-gray-500">{label}</p>
        <p className={`text-2xl font-bold ${valueColour}`}>{value}</p>
      </div>
    )
  }