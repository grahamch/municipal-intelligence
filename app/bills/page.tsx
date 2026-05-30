"use client"

import { checkIsAppPPREnabled } from "next/dist/server/lib/experimental/ppr"
import { useState, useEffect } from "react"

interface Bill {
  id: number
  municipality: string
  period: string
  amount: number
  status: "pending" | "analysed" | "error"
  readType: "actual" | "estimated" | "final"
}

interface CheckResult {
  accountNumber: string
  checks: {
    estimatedRead: {
      passed: boolean
      message: string
    }
  }
}

export default function BillsPage() {
  const [bills, setBills] = useState<Bill[]>([])
  const [checkResult, setCheckResult] = useState<CheckResult | null>(null)

   const addTestBill = () => {
    const newBill: Bill = {
      id: bills.length + 1,
      municipality: "City of Cape Town",
      period: "2026-04",
      amount: 2340.50,
      status: "pending",
      readType: "estimated"
    }
    setBills([...bills, newBill])
    checkBill(newBill)
  }

  const checkBill = async (bill: Bill) => {
    const response = await fetch("/api/check-bill", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        accountNumber: `CHE00${bill.id}`,
        readType: bill.readType
      })
    })
    const result = await response.json()
    setCheckResult(result)
  }

  return (
    <main className="min-h-screen bg-gray-50 p-8">
      <div className="max-w-4xl mx-auto">
        <div className="flex items-center justify-between">
          <h1 className="text-3xl font-bold text-gray-900">Bills</h1>
          <button
            onClick={addTestBill}
            className="bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700"
          >
            Add Test Bill
          </button>
        </div>
        <div className="mt-8 space-y-4">
          {bills.map(bill => (
            <div key={bill.id} className="bg-white rounded-lg p-6 shadow-sm">
              <div className="flex items-center justify-between">
                <div>
                  <p className="font-medium text-gray-900">{bill.municipality}</p>
                  <p className="text-sm text-gray-500">{bill.period}</p>
                </div>
                <div className="text-right">
                  <p className="font-medium text-gray-900">R{bill.amount}</p>
                  <p className="text-sm text-blue-600">{bill.status}</p>
                </div>
              </div>
            </div>
          ))}
          {bills.length === 0 && (
            <p className="text-gray-500 text-center py-12">No bills uploaded yet.</p>
          )}
        </div>
        {checkResult && (
          <div className="mt-8 bg-white rounded-lg p-6 shadow-sm">
            <h2 className="text-lg font-bold text-gray-900 mb-4">Latest Check Result</h2>
            <p className="text-sm text-gray-500">Account: {checkResult.accountNumber}</p>
            <div className="mt-2">
              <p className={`text-sm font-medium ${checkResult.checks.estimatedRead.passed ? "text-green-600" : "text-red-600"}`}>
                Estimated Read: {checkResult.checks.estimatedRead.message}
              </p>
            </div>
          </div>
        )}
      </div>
    </main>
  )
}