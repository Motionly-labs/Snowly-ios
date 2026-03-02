//
//  Item.swift
//  Snowly
//
//  Created by Roy Kid on 2026-03-02.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
