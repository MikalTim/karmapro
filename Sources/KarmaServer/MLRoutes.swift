// by cipher.org.uk
import Foundation
import KarmaCore
import Vapor

/// The body of `GET /api/ml/models`: the library's models and the choices the training and scan forms show.
private struct MLModelsDTO: Encodable {
    let models: [MLService.MLModelDTO]
    let options: MLService.MLOptionsDTO
}

private struct MLTrainBody: Decodable {
    var folder: String
    var language: String
    var name: String
}

private struct MLImportURLBody: Decodable {
    var url: String
}

private struct MLScanBody: Decodable {
    var model: String
    var extensions: [String]?
    var threshold: Double
}

/// Registers the ML routes: the classifier library (training, import, export), project scans and the heatmap.
/// `MLService` holds the logic; training and scans run as jobs whose results are the `MLService` DTOs.
func registerMLRoutes(_ api: RoutesBuilder) {
    // GET /api/ml/models
    //   request: none
    //   response: MLModelsDTO = {"models": [MLModelDTO], "options": MLOptionsDTO}
    api.get("ml", "models") { req async throws -> Response in
        let listing = try await req.service {
            MLModelsDTO(models: MLService.models(), options: MLService.options())
        }
        return jsonResponse(listing)
    }

    // POST /api/ml/train {folder, language, name}
    //   Trains on the +/- lines of the patches under `folder`. 400 for a blank folder, a blank name,
    //   an unknown language or a folder that is not a directory.
    //   response: {"jobId"}; the job result is MLService.MLTrainResultDTO
    api.post("ml", "train") { req async throws -> Response in
        let body = try req.jsonBody(MLTrainBody.self)
        let jobID = try await req.service {
            try MLService.train(folder: body.folder, language: body.language, name: body.name)
        }
        return jobStartedResponse(jobID)
    }

    // GET /api/ml/models/:name/export
    //   response: the model file as a download, named <name>.karmamodel (application/octet-stream).
    //   404 for an unknown model.
    api.get("ml", "models", ":name", "export") { req async throws -> Response in
        guard let name = req.parameters.get("name") else {
            throw Abort(.badRequest, reason: "The path needs a model name.")
        }
        let export = try await req.service { try MLService.exportModel(name: name) }
        return downloadResponse(fileName: export.fileName, data: export.data)
    }

    // POST /api/ml/models/import (raw file body, ?filename=)
    //   request: a .karmamodel or .json model file. 400 for any other file.
    //   response: MLService.MLModelDTO {name}
    api.post("ml", "models", "import") { req async throws -> Response in
        let data = try req.uploadedData()
        let fileName = req.uploadedFileName
        let model = try await req.service { try MLService.importModel(data: data, fileName: fileName) }
        return jsonResponse(model)
    }

    // POST /api/ml/models/import-url {url}
    //   Downloads a model file from the address and adds it to the library. The request waits for the
    //   download (at most a minute). 400 for a blank address or a failed download.
    //   response: MLService.MLModelDTO {name}
    api.post("ml", "models", "import-url") { req async throws -> Response in
        let body = try req.jsonBody(MLImportURLBody.self)
        let model = try await req.service { try MLService.importModel(urlString: body.url) }
        return jsonResponse(model)
    }

    // POST /api/ml/scan {model, extensions?, threshold}
    //   Scans the open project. `extensions` empty means every file; `threshold` is a percentage (1...100).
    //   400 when no project is open, no model is chosen or the threshold is out of range.
    //   response: {"jobId"}; the job result is MLService.MLScanResultDTO
    api.post("ml", "scan") { req async throws -> Response in
        let body = try req.jsonBody(MLScanBody.self)
        let jobID = try await req.service {
            try MLService.scan(model: body.model, extensions: body.extensions ?? [], threshold: body.threshold)
        }
        return jobStartedResponse(jobID)
    }

    // GET /api/ml/heatmap
    //   request: none
    //   response: MLService.HeatmapDTO of the most recent scan (empty before the first scan)
    api.get("ml", "heatmap") { req async throws -> Response in
        let heatmap = try await req.service { MLService.heatmap() }
        return jsonResponse(heatmap)
    }
}
