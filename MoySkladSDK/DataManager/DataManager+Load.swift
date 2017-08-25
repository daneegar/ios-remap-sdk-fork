//
//  DataManager+Load.swift
//  MoyskladNew
//
//  Created by Andrey Parshakov on 04.04.17.
//  Copyright © 2017 Andrey Parshakov. All rights reserved.
//

import Foundation
import RxSwift

public typealias groupedMoment<K>  = (date: Date, data: [MSEntity<K.Element>])  where K: MSGeneralDocument, K: DictConvertable

extension DataManager {
    static func loadUrl<T: MSBaseDocumentType>(type: T.Type) -> MSApiRequest {
        switch type {
        case is MSCustomerOrder.Type:
            return .customerorder
        case is MSDemand.Type:
            return .demand
        case is MSInvoice.Type:
            return .invoiceOut
        case is MSCashInOut.Type:
            return .cashIn
        default:
            return .customerorder
        }
    }
    
    static func loadUrlTemplate<T: MSBaseDocumentType>(type: T.Type) -> MSApiRequest {
        switch type {
        case is MSCustomerOrder.Type:
            return .customerordermetadata
        case is MSDemand.Type:
            return .demandmetadata
        case is MSInvoice.Type:
            return .invoiceOutMetadata
        case is MSCashInOut.Type:
            return .cashInMetadata
        default:
            return .customerordermetadata
        }
    }
    
    static func loadError<T: MSBaseDocumentType>(type: T.Type) -> MSError {
        switch T.self {
        case is MSCustomerOrder.Type:
            return MSError.genericError(errorText: LocalizedStrings.incorrectCustomerOrdersResponse.value)
        case is MSDemand.Type:
            return MSError.genericError(errorText: LocalizedStrings.incorrectDemandsResponse.value)
        case is MSInvoice.Type:
            return MSError.genericError(errorText: LocalizedStrings.incorrectInvoicesOutResponse.value)
        default:
            return MSError.genericError(errorText: LocalizedStrings.incorrectCustomerOrdersResponse.value)
        }
    }
    
    static func loadPositionsError<T: MSGeneralDocument>(type: T.Type) -> MSError {
        switch T.self {
        case is MSCustomerOrder.Type:
            return MSError.genericError(errorText: LocalizedStrings.incorrectCustomerOrdersResponse.value)
        case is MSDemand.Type:
            return MSError.genericError(errorText: LocalizedStrings.incorrectDemandsResponse.value)
        case is MSInvoice.Type:
            return MSError.genericError(errorText: LocalizedStrings.incorrectInvoicesOutResponse.value)
        default:
            return MSError.genericError(errorText: LocalizedStrings.incorrectCustomerOrdersResponse.value)
        }
    }
    
    /**
     Load document by Id
     - parameter Id: Id of document to load
     - parameter auth: Authentication information
     - parameter documentId: Document Id
     - parameter expanders: Additional objects to include into request
     */
    public static func loadById<T>(doc: T.Type, auth: Auth, documentId : UUID, expanders: [Expander] = []) -> Observable<MSEntity<T.Element>>  where T: MSBaseDocumentType, T: DictConvertable {
        return HttpClient.get(loadUrl(type: T.self), auth: auth, urlPathComponents: [documentId.uuidString], urlParameters: [CompositeExpander(expanders)])
            .flatMapLatest { result -> Observable<MSEntity<T.Element>> in
                guard let result = result else { return Observable.error(loadError(type: T.self)) }
                
                guard let deserialized = T.from(dict: result) else {
                    return Observable.error(loadError(type: T.self))
                }
                
                return Observable.just(deserialized)
        }
    }
    
    /**
     Load counterparty by Id
     - parameter Id: Id of counterparty to load
     - parameter auth: Authentication information
     - parameter documentId: counterparty Id
     - parameter expanders: Additional objects to include into request
     */
    public static func loadById(auth: Auth, counterpartyId: UUID, expanders: [Expander] = []) -> Observable<MSEntity<MSAgent>> {
        return HttpClient.get(.counterparty, auth: auth, urlPathComponents: [counterpartyId.uuidString], urlParameters: [CompositeExpander(expanders)])
            .flatMapLatest { result -> Observable<MSEntity<MSAgent>> in
                guard let result = result else { return Observable.error(MSError.genericError(errorText: LocalizedStrings.incorrectCounterpartyResponse.value)) }
                
                guard let deserialized = MSAgent.from(dict: result) else {
                    return Observable.error(MSError.genericError(errorText: LocalizedStrings.incorrectCounterpartyResponse.value))
                }
                
                return Observable.just(deserialized)
        }
    }
    
    /**
     Load counterparty report by Id
     - parameter auth: Authentication information
     - parameter counterpartyId: Id of counterparty
     */
    public static func loadReportById(auth: Auth, counterpartyId: UUID) -> Observable<MSEntity<MSAgentReport>> {
        return HttpClient.get(.counterpartyReport, auth: auth, urlPathComponents: [counterpartyId.uuidString])
            .flatMapLatest { result -> Observable<MSEntity<MSAgentReport>> in
                guard let result = result else { return Observable.error(MSError.genericError(errorText: LocalizedStrings.incorrectCounterpartyReportResponse.value)) }
                
                guard let deserialized = MSAgentReport.from(dict: result) else {
                    return Observable.error(MSError.genericError(errorText: LocalizedStrings.incorrectCounterpartyReportResponse.value))
                }
                
                return Observable.just(deserialized)
        }
    }
    
    /**
     Load reports for specified counterparties
     - parameter auth: Authentication information
     - parameter counterparties: Array of counterparties
    */
    public static func loadReportsForCounterparties(auth: Auth, counterparties: [MSEntity<MSAgent>]) -> Observable<[MSEntity<MSAgentReport>]> {
        guard counterparties.count > 0 else { return .just([]) }
        
        let body: [String: Any] = ["counterparties": counterparties.map { ["counterparty": ["meta": $0.objectMeta().dictionary()]] }]
        
        return HttpClient.create(.counterpartyReport, auth: auth, body: body, contentType: .json)
            .flatMapLatest { result -> Observable<[MSEntity<MSAgentReport>]> in
                guard let result = result else { return Observable.error(MSError.genericError(errorText: LocalizedStrings.incorrectCounterpartyReportResponse.value)) }
                
                let deserialized = result.msArray("rows").flatMap { MSAgentReport.from(dict: $0) }
                
                return Observable.just(deserialized)
        }
    }
    
    /**
     Load documents and group by document moment
     - parameter docType: Type of document
     - parameter auth: Authentication information
     - parameter offset: Desired data offset
     - parameter expanders: Additional objects to include into request
     - parameter filter: Filter for request
     - parameter search: Additional string for filtering by name
     - parameter organizationId: Id of organization to filter by
     - parameter stateId: If of state to filter by
     - parameter withPrevious: Grouped data returned by previous invocation of groupedByMoment (useful for paged loading)
    */
    public static func groupedByMoment<T>(docType: T.Type,
                                       auth: Auth,
                                       offset: MSOffset? = nil,
                                       expanders: [Expander] = [],
                                       filter: Filter? = nil,
                                       search: Search? = nil,
                                       organizationId: OrganizationIdParameter? = nil,
                                       stateId: StateIdParameter? = nil,
                                       withPrevious: [groupedMoment<T>]? = nil)
        -> Observable<[groupedMoment<T>]> where T: MSBaseDocumentType, T: DictConvertable, T.Element: MSBaseDocumentType   {
            return DataManager.load(docType: docType, auth: auth, offset: offset, expanders: expanders, filter: filter, search: search,organizationId: organizationId, stateId: stateId, orderBy: Order(OrderArgument(field: .moment)))
                .flatMapLatest { result -> Observable<[groupedMoment<T>]> in
                    let grouped = DataManager.groupByDate2(data: result, withPrevious: withPrevious)
                    return Observable.just(grouped)
            }
    }
    
    /**
     Load documents
     - parameter docType: Type of document
     - parameter auth: Authentication information
     - parameter offset: Desired data offset
     - parameter expanders: Additional objects to include into request
     - parameter filter: Filter for request
     - parameter search: Additional string for filtering by name
     - parameter organizationId: Id of organization to filter by
     - parameter stateId: If of state to filter by
    */
    public static func load<T>(docType: T.Type,
                            auth: Auth,  
                            offset: MSOffset? = nil, 
                            expanders: [Expander] = [],
                            filter: Filter? = nil,
                            search: Search? = nil,
                            organizationId: OrganizationIdParameter? = nil,
                            stateId: StateIdParameter? = nil,
                            orderBy: Order? = nil) -> Observable<[MSEntity<T.Element>]> where T: MSBaseDocumentType, T: DictConvertable  {
        
        let urlParameters: [UrlParameter] = mergeUrlParameters(search, stateId, organizationId, offset, filter, orderBy, CompositeExpander(expanders))
        
        return HttpClient.get(loadUrl(type: T.self), auth: auth, urlParameters: urlParameters)
            .flatMapLatest { result -> Observable<[MSEntity<T.Element>]> in
                guard let result = result else { return Observable.error(loadError(type: T.self)) }
                
                let deserialized = result.msArray("rows").flatMap { T.from(dict: $0) }
                
                return Observable.just(deserialized)
        }
    }
    
    /**
     Load document positions
     - parameter docType: Type of document
     - parameter auth: Authentication information
     - parameter documentId: Document Id
     - parameter offset: Desired data offset
     - parameter expanders: Additional objects to include into request
     - parameter filter: Filter for request
     - parameter search: Additional string for filtering by name
    */
    public static func loadPositions<T>(docType: T.Type, 
                                     auth: Auth, 
                                     documentId : UUID,
                                     offset: MSOffset? = nil, 
                                     expanders: [Expander] = [],
                                     filter: Filter? = nil, 
                                     search: Search? = nil) -> Observable<[MSEntity<MSPosition>]> where T: MSGeneralDocument, T: DictConvertable, T.Element: MSGeneralDocument{
        let urlParameters: [UrlParameter] = mergeUrlParameters(offset, search, CompositeExpander(expanders), filter)
        return HttpClient.get(loadUrl(type: T.self), auth: auth, urlPathComponents: [documentId.uuidString, "positions"],
                              urlParameters: urlParameters)
            .flatMapLatest { result -> Observable<[MSEntity<MSPosition>]> in
                guard let result = result else { return Observable.error(loadPositionsError(type: T.self)) }
                
                if let size: Int = result.msValue("meta").value("size"), size > DataManager.documentPositionsCountLimit {
                    return Observable.error(MSError.genericError(errorText: LocalizedStrings.documentTooManyPositions.value))
                }
                
                let deserialized = result.msArray("rows").map { MSPosition.from(dict: $0) }
                let withoutNills = deserialized.removeNils()
                
                guard withoutNills.count == deserialized.count else {
                    return Observable.error(loadPositionsError(type: T.self))
                }
                
                return Observable.just(withoutNills)
        }
    }
}
