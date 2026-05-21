"use client"

import { useState } from "react"

export default function BillsPage() {
  const [count, setCount] = useState(0)

  return (
    <main className="min-h-screen bg-gray-50 p-8">
      <div className="max-w-4xl mx-auto">
        <h1 className="text-3xl font-bold text-gray-900">Bills</h1>
        <p className="mt-2 text-gray-600">Your uploaded municipal bills.</p>
        <div className="mt-8">
          <p className="text-lg">Bills uploaded: {count}</p>
          <button 
            onClick={() => setCount(count + 1)}
            className="mt-4 bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700"
          >
            Upload Bill
          </button>
          <button 
            onClick={() => setCount(0)}
            className="mt-4 ml-4 bg-gray-200 text-gray-700 px-4 py-2 rounded-lg hover:bg-gray-300"
          >
            Reset Count
          </button>
        </div>
      </div>
    </main>
  )
}