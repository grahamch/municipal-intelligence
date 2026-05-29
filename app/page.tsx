import StatCard from "./components/StatCard"

export default function Home() {
  return (
    <main className="min-h-screen bg-gray-50 p-8">
      <div className="max-w-4xl mx-auto">
        <h1 className="text-3xl font-bold text-gray-900">
          Municipal Billing Intelligence
        </h1>
        <p className="mt-2 text-gray-600">
          Detecting billing errors across South African municipalities.
        </p>
        <div className="mt-8 grid grid-cols-3 gap-4">
          <StatCard label="Bills Analysed" value="0" />
          <StatCard label="Errors Detected" value="0" valueColour="text-red-600" />
          <StatCard label="Amount Recoverable" value="R0" valueColour="text-green-600" />
        </div>
      </div>
    </main>
  )
}