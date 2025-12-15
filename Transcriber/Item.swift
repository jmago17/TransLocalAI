//
//  Item.swift
//  Transcriber
//
//  Created by Josu Martinez Gonzalez on 15/12/25.
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
