"use client"

import { useState } from "react"

interface Property {
  name: string
  address: string
  amount: number
  status: "current" | "arrears"
}

//Each property shows: name, address, monthly levy amount, and a status of either "current" or "arrears"
//Properties in arrears should show their status in red, current in green
//An empty state message when no properties exist

export default function PropertyPage() {
  const [properties, setProperty] = useState<Property[]>([])

  const addTestProperty = () => {
    const newProperty: Property = {
      name: "Prtoperty name" + 1,
      address: "42 Sea Glade, 12 Milner Avenue, Hout Bay, Cape Town, 7806",
      amount: 2340.50,
      status: "current"
    }
    setProperty([...properties, newProperty])
  }

  return (
    <main className="min-h-screen bg-gray-50 p-8">
      <div className="max-w-4xl mx-auto">
        <div className="flex items-center justify-between">
          <h1 className="text-3xl font-bold text-gray-900">Properties</h1>
          <button
            onClick={addTestProperty}
            className="bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700"
          >
            Add Test Property
          </button>
        </div>
        <div className="mt-8 space-y-4">
          {properties.map(property => (
            <div className="bg-white rounded-lg p-6 shadow-sm">
              <div className="flex items-center justify-between">
                <div>
                  <p className="font-medium text-gray-900">{property.name}</p>
                  <p className="text-sm text-gray-500">{property.address}</p>
                </div>
                <div className="text-right">
                  <p className="font-medium text-gray-900">R{property.amount}</p>
                  <p className="text-sm text-blue-600">{property.status}</p>
                </div>
              </div>
            </div>
          ))}
          {properties.length === 0 && (
            <p className="text-gray-500 text-center py-12">No properties uploaded yet.</p>
          )}
        </div>
      </div>
    </main>
  )
}